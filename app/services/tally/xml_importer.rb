require "digest"
require "nokogiri"

module Tally
  class XmlImporter
    MAX_FILE_SIZE = 50.megabytes

    # ------------------------------------------------------------
    # Custom exceptions
    # ------------------------------------------------------------

    class InvalidXmlError < StandardError
    end

    class UnsupportedDocumentError < StandardError
    end

    class EncodingError < StandardError
    end

    class FileTooLargeError < StandardError
    end

    # ------------------------------------------------------------
    # Result object
    # ------------------------------------------------------------

    Result = Struct.new(
      :document_type,
      :status,
      :detected_encoding,
      :warnings,
      :errors,
      :vouchers,
      :tally_response,
      keyword_init: true
    )

    # ------------------------------------------------------------
    # Initializer
    # ------------------------------------------------------------

    def initialize(bytes:)
      @bytes = bytes
      @warnings = []
      @errors = []
    end

    # ------------------------------------------------------------
    # Main entry point
    # ------------------------------------------------------------

    def call
      validate_file_size!

      detected_encoding = detect_encoding

      xml = decode_bytes(detected_encoding)
      xml = normalize_xml_declaration(xml)
      xml = sanitize_xml(xml)
      document = parse_xml(xml)

      root = document.root

      if root.nil?
        raise InvalidXmlError, "XML document has no root element"
      end

      case root.name
      when "ENVELOPE"
        parse_envelope(
          document,
          detected_encoding
        )

      when "RESPONSE"
        parse_response(
          document,
          detected_encoding
        )

      else
        raise UnsupportedDocumentError,
              "Unsupported XML root element: #{root.name}"
      end
    end

    private

    # ============================================================
    # File validation
    # ============================================================

    def normalize_xml_declaration(xml)
      xml.sub(
        /\A\s*<\?xml\b[^?]*\?>/i
      ) do |declaration|
        declaration
          .sub(/encoding\s*=\s*["'][^"']+["']/i, 'encoding="UTF-8"')
      end
    end
    
    def validate_file_size!
      return if @bytes.bytesize <= MAX_FILE_SIZE

      raise FileTooLargeError,
            "Uploaded file exceeds the maximum allowed size"
    end

    # ============================================================
    # Encoding detection
    # ============================================================

    def detect_encoding
      bytes = @bytes

      # UTF-8 BOM
      if bytes.start_with?("\xEF\xBB\xBF".b)
        return "UTF-8"
      end

      # UTF-16 Little Endian BOM
      if bytes.start_with?("\xFF\xFE".b)
        return "UTF-16LE"
      end

      # UTF-16 Big Endian BOM
      if bytes.start_with?("\xFE\xFF".b)
        return "UTF-16BE"
      end

      # XML declaration
      header = bytes.byteslice(0, 500)

      if header
        ascii_header = header.dup.force_encoding(Encoding::ASCII_8BIT)

        if ascii_header =~ /encoding\s*=\s*["']UTF-16["']/i
          return detect_utf16_endianness(bytes)
        end

        if ascii_header =~ /encoding\s*=\s*["']UTF-16LE["']/i
          return "UTF-16LE"
        end

        if ascii_header =~ /encoding\s*=\s*["']UTF-16BE["']/i
          return "UTF-16BE"
        end

        if ascii_header =~ /encoding\s*=\s*["']UTF-8["']/i
          return "UTF-8"
        end
      end

      # Detect UTF-16 without BOM using zero bytes.
      if looks_like_utf16_le?(bytes)
        return "UTF-16LE"
      end

      if looks_like_utf16_be?(bytes)
        return "UTF-16BE"
      end

      "UTF-8"
    end

    def detect_utf16_endianness(bytes)
      return "UTF-16LE" if bytes.bytesize >= 2 && bytes.getbyte(0) == 0xFF && bytes.getbyte(1) == 0xFE
      return "UTF-16BE" if bytes.bytesize >= 2 && bytes.getbyte(0) == 0xFE && bytes.getbyte(1) == 0xFF

      # UTF-16 XML normally has zero bytes between ASCII characters.
      return "UTF-16LE" if looks_like_utf16_le?(bytes)
      return "UTF-16BE" if looks_like_utf16_be?(bytes)

      "UTF-16LE"
    end

    def looks_like_utf16_le?(bytes)
      sample = bytes.byteslice(0, 200)

      return false if sample.nil? || sample.bytesize < 4

      zero_odd_positions = 0
      checked = 0

      sample.bytes.each_slice(2) do |pair|
        break if pair.length < 2

        checked += 1
        zero_odd_positions += 1 if pair[1] == 0
      end

      checked > 5 && (zero_odd_positions.to_f / checked) > 0.30
    end

    def looks_like_utf16_be?(bytes)
      sample = bytes.byteslice(0, 200)

      return false if sample.nil? || sample.bytesize < 4

      zero_even_positions = 0
      checked = 0

      sample.bytes.each_slice(2) do |pair|
        break if pair.length < 2

        checked += 1
        zero_even_positions += 1 if pair[0] == 0
      end

      checked > 5 && (zero_even_positions.to_f / checked) > 0.30
    end

    # ============================================================
    # Decode bytes
    # ============================================================

    def decode_bytes(encoding)
      case encoding
      when "UTF-8"
        decode_utf8

      when "UTF-16LE"
        decode_utf16("UTF-16LE")

      when "UTF-16BE"
        decode_utf16("UTF-16BE")

      else
        raise EncodingError,
              "Unsupported encoding: #{encoding}"
      end
    end

    def decode_utf8
      data = @bytes.dup

      # Remove UTF-8 BOM before parsing.
      data = data.byteslice(3..) if data.start_with?("\xEF\xBB\xBF".b)

      xml = data.force_encoding(Encoding::UTF_8)

      unless xml.valid_encoding?
        raise EncodingError,
              "Uploaded file is not valid UTF-8"
      end

      xml
    end

    def decode_utf16(encoding)
      data = @bytes.dup

      # Remove BOM because we explicitly specify the encoding.
      if encoding == "UTF-16LE" && data.start_with?("\xFF\xFE".b)
        data = data.byteslice(2..)
      elsif encoding == "UTF-16BE" && data.start_with?("\xFE\xFF".b)
        data = data.byteslice(2..)
      end

      ruby_encoding = Encoding.find(encoding)

      xml = data.force_encoding(ruby_encoding).encode(
        Encoding::UTF_8,
        invalid: :replace,
        undef: :replace
      )

      unless xml.valid_encoding?
        raise EncodingError,
              "Unable to decode UTF-16 XML"
      end

      xml
    rescue Encoding::InvalidByteSequenceError,
           Encoding::UndefinedConversionError => e
      raise EncodingError, e.message
    end

    # ============================================================
    # XML sanitization
    # ============================================================

    def sanitize_xml(xml)
      original = xml.dup

      # XML 1.0 does not allow most C0 control characters.
      #
      # The assignment fixture contains:
      #
      #   &#4;
      #
      # This is a recoverable control reference. Remove the
      # reference instead of allowing the XML parser to fail.
      sanitized = xml.gsub(
        /&#(?:x0*[0-8bBcCeEfF]|0*[0-1][0-9]|0*1[0-9]|0*1[0-9]?);/i
      ) do
        @warnings << {
          code: "SANITIZED_XML_CONTROL_REFERENCE",
          message: "Removed an illegal XML control character reference"
        }

        ""
      end

      # Handle numeric character references for C0 controls more
      # explicitly. This covers values such as &#4;.
      sanitized = sanitized.gsub(/&#([0-9]+);/) do |match|
        codepoint = Regexp.last_match(1).to_i

        if illegal_xml_10_codepoint?(codepoint)
          @warnings << {
            code: "SANITIZED_XML_CONTROL_REFERENCE",
            message: "Removed illegal XML control character reference #{match}"
          }

          ""
        else
          match
        end
      end

      # Hexadecimal references such as &#x4;
      sanitized = sanitized.gsub(/&#x([0-9a-fA-F]+);/) do |match|
        codepoint = Regexp.last_match(1).to_i(16)

        if illegal_xml_10_codepoint?(codepoint)
          @warnings << {
            code: "SANITIZED_XML_CONTROL_REFERENCE",
            message: "Removed illegal XML control character reference #{match}"
          }

          ""
        else
          match
        end
      end

      if sanitized != original
        @warnings << {
          code: "XML_SANITIZED",
          message: "Recoverable XML sanitization was performed"
        }
      end

      sanitized
    end

    def illegal_xml_10_codepoint?(codepoint)
      # XML 1.0 valid character ranges:
      #
      # #x9, #xA, #xD
      # #x20-#xD7FF
      # #xE000-#xFFFD
      # #x10000-#x10FFFF
      #
      # Everything else is invalid.
      !(
        codepoint == 0x9 ||
        codepoint == 0xA ||
        codepoint == 0xD ||
        (0x20..0xD7FF).cover?(codepoint) ||
        (0xE000..0xFFFD).cover?(codepoint) ||
        (0x10000..0x10FFFF).cover?(codepoint)
      )
    end

    # ============================================================
    # Secure XML parsing
    # ============================================================

    def parse_xml(xml)
      options =
        Nokogiri::XML::ParseOptions::DEFAULT_XML |
        Nokogiri::XML::ParseOptions::NONET

      document = Nokogiri::XML::Document.parse(
        xml,
        nil,
        "UTF-8",
        options
      )

      if document.errors.any?
        errors = document.errors.map(&:message).join("; ")

        raise InvalidXmlError, errors
      end

      document
    rescue Nokogiri::XML::SyntaxError => e
      raise InvalidXmlError, e.message
    end

    # ============================================================
    # ENVELOPE
    # ============================================================

    def parse_envelope(document, detected_encoding)
      collection = document.at_xpath(
        "/ENVELOPE/BODY/DATA/COLLECTION"
      )

      unless collection
        raise UnsupportedDocumentError,
              "ENVELOPE does not contain BODY/DATA/COLLECTION"
      end

      vouchers = []

      # IMPORTANT:
      # Only direct VOUCHER children are considered.
      collection.element_children.each do |node|
        next unless node.name == "VOUCHER"

        vouchers << parse_voucher(
          node,
          vouchers.length
        )
      end

      Result.new(
        document_type: "voucherExport",
        status: "completed",
        detected_encoding: detected_encoding,
        warnings: @warnings,
        errors: @errors,
        vouchers: vouchers,
        tally_response: nil
      )
    end

    # ============================================================
    # Voucher
    # ============================================================

    def parse_voucher(voucher_node, voucher_index)
      data = {
        voucher_index: voucher_index,
        xml_attributes: {},
        warnings: [],
        ledger_entries: [],
        inventory_entries: []
      }

      # Preserve voucher xml_attributes.
      voucher_node.attribute_nodes.each do |attribute|
        data[:xml_attributes][attribute.name] = attribute.value
      end

      # IMPORTANT:
      # Only direct children are processed.
      voucher_node.element_children.each do |node|
        case node.name

        when "DATE"
          data[:date] = node.text

        when "VOUCHERTYPENAME"
          data[:voucher_type] = node.text

        when "VOUCHERNUMBER"
          data[:voucher_number] = node.text

        when "PARTYLEDGERNAME"
          data[:party_ledger_name] = node.text

        when "NARRATION"
          data[:narration] = node.text

        when "ALLLEDGERENTRIES.LIST"
          data[:ledger_entries] << parse_ledger_entry(
            node,
            data[:ledger_entries].length
          )

        when "LEDGERENTRIES.LIST"
          data[:ledger_entries] << parse_ledger_entry(
            node,
            data[:ledger_entries].length
          )

        when "ALLINVENTORYENTRIES.LIST"
          data[:inventory_entries] << parse_inventory_entry(
            node,
            data[:inventory_entries].length
          )

        when "INVENTORYENTRIES.LIST"
          data[:inventory_entries] << parse_inventory_entry(
            node,
            data[:inventory_entries].length
          )

        else
          add_unknown_node_warning(
            data[:warnings],
            "VOUCHER",
            node.name
          )
        end
      end

      data
    end

    # ============================================================
    # Ledger entry
    # ============================================================

    def parse_ledger_entry(node, position)
      data = {
        position: position,
        source_tag: node.name,
        bill_allocations: [],
        bank_allocations: [],
        rate_details: []
      }

      # Direct attributes are preserved.
      data[:xml_attributes] = {}

      node.attribute_nodes.each do |attribute|
        data[:xml_attributes][attribute.name] = attribute.value
      end

      node.element_children.each do |child|
        case child.name

        when "LEDGERNAME"
          data[:ledger_name] = child.text

        when "ISDEEMEDPOSITIVE"
          data[:is_deemed_positive] = child.text

        when "AMOUNT"
          data[:amount] = child.text

        when "BILLALLOCATIONS.LIST"
          data[:bill_allocations] << parse_bill_allocation(
            child,
            data[:bill_allocations].length
          )

        when "BANKALLOCATIONS.LIST"
          data[:bank_allocations] << parse_bank_allocation(
            child,
            data[:bank_allocations].length
          )

        when "RATEDETAILS.LIST"
          data[:rate_details] << parse_rate_detail(
            child,
            data[:rate_details].length
          )

        else
          # Unknown fields are ignored but recorded as warnings.
          data[:warnings] ||= []

          add_unknown_node_warning(
            data[:warnings],
            node.name,
            child.name
          )
        end
      end

      data
    end

    # ============================================================
    # Bill allocation
    # ============================================================

    def parse_bill_allocation(node, position)
      data = {
        position: position
      }

      node.element_children.each do |child|
        case child.name

        when "NAME"
          data[:name] = child.text

        when "BILLTYPE"
          data[:bill_type] = child.text

        when "AMOUNT"
          data[:amount] = child.text

        else
          # Ignore unsupported fields.
        end
      end

      data
    end

    # ============================================================
    # Bank allocation
    # ============================================================

    def parse_bank_allocation(node, position)
      data = {
        position: position
      }

      node.element_children.each do |child|
        case child.name

        when "DATE"
          data[:date] = child.text

        when "NAME"
          data[:name] = child.text

        when "TRANSACTIONTYPE"
          data[:transaction_type] = child.text

        when "AMOUNT"
          data[:amount] = child.text

        else
          # Ignore unsupported fields.
        end
      end

      data
    end

    # ============================================================
    # Inventory entry
    # ============================================================

    def parse_inventory_entry(node, position)
      data = {
        position: position,
        source_tag: node.name,
        batch_allocations: [],
        accounting_allocations: [],
        rate_details: []
      }

      data[:xml_attributes] = {}

      node.attribute_nodes.each do |attribute|
        data[:xml_attributes][attribute.name] = attribute.value
      end

      node.element_children.each do |child|
        case child.name

        when "STOCKITEMNAME"
          data[:stock_item_name] = child.text

        when "ISDEEMEDPOSITIVE"
          data[:is_deemed_positive] = child.text

        when "ACTUALQTY"
          data[:actual_qty] = child.text

        when "BILLEDQTY"
          data[:billed_qty] = child.text

        when "RATE"
          data[:rate] = child.text

        when "AMOUNT"
          data[:amount] = child.text

        when "BATCHALLOCATIONS.LIST"
          data[:batch_allocations] << parse_batch_allocation(
            child,
            data[:batch_allocations].length
          )

        when "ACCOUNTINGALLOCATIONS.LIST"
          data[:accounting_allocations] << parse_accounting_allocation(
            child,
            data[:accounting_allocations].length
          )

        when "RATEDETAILS.LIST"
          data[:rate_details] << parse_rate_detail(
            child,
            data[:rate_details].length
          )

        else
          data[:warnings] ||= []

          add_unknown_node_warning(
            data[:warnings],
            node.name,
            child.name
          )
        end
      end

      data
    end

    # ============================================================
    # Batch allocation
    # ============================================================

    def parse_batch_allocation(node, position)
      data = {
        position: position
      }

      node.element_children.each do |child|
        case child.name

        when "GODOWNNAME"
          data[:godown_name] = child.text

        when "BATCHNAME"
          data[:batch_name] = child.text

        when "ACTUALQTY"
          data[:actual_qty] = child.text

        when "BILLEDQTY"
          data[:billed_qty] = child.text

        when "AMOUNT"
          data[:amount] = child.text

        else
          # Ignore unsupported fields.
        end
      end

      data
    end

    # ============================================================
    # Accounting allocation
    # ============================================================

    def parse_accounting_allocation(node, position)
      data = {
        position: position,
        rate_details: []
      }

      node.element_children.each do |child|
        case child.name

        when "LEDGERNAME"
          data[:ledger_name] = child.text

        when "ISDEEMEDPOSITIVE"
          data[:is_deemed_positive] = child.text

        when "AMOUNT"
          data[:amount] = child.text

        when "RATEDETAILS.LIST"
          data[:rate_details] << parse_rate_detail(
            child,
            data[:rate_details].length
          )

        else
          # Ignore unsupported fields.
        end
      end

      data
    end

    # ============================================================
    # Rate detail
    # ============================================================

    def parse_rate_detail(node, position)
      data = {
        position: position
      }

      node.element_children.each do |child|
        case child.name
        when "GSTRATEDUTYHEAD"
          data[:duty_head] = child.text
        when "DUTYHEAD"
          data[:duty_head] = child.text
        when "GSTRATE"
          data[:rate] = child.text
        end
      end

      data
    end

    # ============================================================
    # Tally RESPONSE
    # ============================================================

    def parse_response(document, detected_encoding)
      root = document.root

      counters = {}

      %w[
        CREATED
        ALTERED
        DELETED
        IGNORED
        ERRORS
      ].each do |field|
        node = direct_child(root, field)

        counters[field] = node.text if node
      end

      line_error_node = direct_child(
        root,
        "LINEERROR"
      )

      line_error = line_error_node&.text

      errors_count = counters["ERRORS"].to_i

      business_status =
        if errors_count.positive? || line_error.present?
          "failed"
        else
          "succeeded"
        end

      tally_response = {
        business_status: business_status,
        counters: counters,
        line_error: line_error
      }

      Result.new(
        document_type: "tallyResponse",
        status: "completed",
        detected_encoding: detected_encoding,
        warnings: @warnings,
        errors: @errors,
        vouchers: [],
        tally_response: tally_response
      )
    end

    # ============================================================
    # Helpers
    # ============================================================

    def direct_child(parent, name)
      parent.element_children.find do |child|
        child.name == name
      end
    end

    def add_unknown_node_warning(warnings, parent_name, node_name)
      warnings << {
        code: "UNKNOWN_XML_NODE",
        message: "Unknown XML node '#{node_name}' under #{parent_name}"
      }
    end
  end
end