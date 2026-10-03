class ImportsController < ApplicationController
  # POST /imports
  def create
    file = params[:file]

    if file.blank?
      return render_error(
        code: "FILE_REQUIRED",
        message: "multipart field 'file' is required",
        status: :bad_request
      )
    end

    bytes = file.read

    if bytes.blank?
      return render_error(
        code: "EMPTY_FILE",
        message: "Uploaded file is empty",
        status: :bad_request
      )
    end

    # Generate SHA-256 from the exact uploaded bytes.
    content_hash = Digest::SHA256.hexdigest(bytes)

    # ------------------------------------------------------------
    # Idempotency check
    # ------------------------------------------------------------
    existing_import = Import.find_by(
      content_hash: content_hash
    )

    if existing_import
      return render json: import_response(
        existing_import,
        duplicate: true
      ), status: :ok
    end

    # ------------------------------------------------------------
    # Parse XML
    # ------------------------------------------------------------
    result = Tally::XmlImporter.new(
      bytes: bytes
    ).call

    # ------------------------------------------------------------
    # Persist import atomically
    # ------------------------------------------------------------
    import = nil

    begin
      import = Import.transaction(requires_new: true) do
        created_import = Import.create!(
          content_hash: content_hash,
          document_type: result.document_type,
          status: result.status,
          detected_encoding: result.detected_encoding,
          warnings: result.warnings || [],
          error_messages: result.errors || [],
          raw_source: bytes
        )

        persist_result!(
          created_import,
          result
        )

        created_import
      end

    rescue ActiveRecord::RecordNotUnique
      # Handles the race condition where two requests upload
      # exactly the same XML at the same time.
      import = Import.find_by!(
        content_hash: content_hash
      )

      return render json: import_response(
        import,
        duplicate: true
      ), status: :ok
    end

    render json: import_response(
      import,
      duplicate: false
    ), status: :created

  rescue Tally::XmlImporter::InvalidXmlError => e
    render_error(
      code: "INVALID_XML",
      message: e.message,
      status: :unprocessable_entity
    )

  rescue Tally::XmlImporter::UnsupportedDocumentError => e
    render_error(
      code: "UNSUPPORTED_DOCUMENT",
      message: e.message,
      status: :unprocessable_entity
    )

  rescue Tally::XmlImporter::EncodingError => e
    render_error(
      code: "INVALID_ENCODING",
      message: e.message,
      status: :unprocessable_entity
    )

  rescue Tally::XmlImporter::FileTooLargeError => e
    render_error(
      code: "FILE_TOO_LARGE",
      message: e.message,
      status: :payload_too_large
    )

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error(
      "[Tally Import] RecordInvalid: #{e.message}"
    )

    render_error(
      code: "PERSISTENCE_ERROR",
      message: e.message,
      status: :unprocessable_entity
    )

  rescue StandardError => e
    Rails.logger.error(
      "[Tally Import] #{e.class}: #{e.message}"
    )

    render_error(
      code: "IMPORT_FAILED",
      message: "Unable to process the XML file",
      status: :unprocessable_entity
    )
  end
  # rescue StandardError => e
  #   Rails.logger.error "=" * 80
  #   Rails.logger.error "[TALLY IMPORT ERROR]"
  #   Rails.logger.error "Class: #{e.class}"
  #   Rails.logger.error "Message: #{e.message}"
  #   Rails.logger.error "Backtrace:"
  #   Rails.logger.error e.backtrace.join("\n")
  #   Rails.logger.error "=" * 80

  #   render json: {
  #     error: {
  #       code: "IMPORT_FAILED",
  #       message: e.message,
  #       exception: e.class.name,
  #       backtrace: Rails.env.development? ? e.backtrace.first(10) : []
  #     }
  #   }, status: :unprocessable_entity
  # end

  # GET /imports/:id
  def show
    import = Import.find(params[:id])

    render json: import_details(import), status: :ok

  rescue ActiveRecord::RecordNotFound
    render_error(
      code: "IMPORT_NOT_FOUND",
      message: "Import not found",
      status: :not_found
    )
  end

  # GET /imports/:id/vouchers
  def vouchers
    import = Import.find(params[:id])

    vouchers = import.vouchers.order(:voucher_index)

    render json: {
      items: vouchers.map do |voucher|
        Tally::VoucherSerializer.new(voucher).as_json
      end,
      count: vouchers.size
    }, status: :ok

  rescue ActiveRecord::RecordNotFound
    render_error(
      code: "IMPORT_NOT_FOUND",
      message: "Import not found",
      status: :not_found
    )
  end

  private

  # ============================================================
  # Persist parsed XML result
  # ============================================================

  def persist_result!(import, result)
    Array(result.vouchers).each do |voucher_data|
      persist_voucher!(
        import,
        voucher_data
      )
    end

    if result.tally_response.present?
      import.update!(
        tally_response: result.tally_response
      )
    end
  end

  # ============================================================
  # Persist voucher
  # ============================================================

  def persist_voucher!(import, data)
    voucher_warnings = Array(data[:warnings])

    voucher = import.vouchers.create!(
      voucher_index: data[:voucher_index],
      date: data[:date],
      voucher_type: data[:voucher_type],
      voucher_number: data[:voucher_number],
      party_ledger_name: data[:party_ledger_name],
      narration: data[:narration],
      xml_attributes: data[:xml_attributes] || {},
      warnings: voucher_warnings
    )

    if voucher_warnings.any?
      import.update!(
        warnings: Array(import.warnings) + voucher_warnings
      )
    end

    # ----------------------------------------------------------
    # Ledger entries
    # ----------------------------------------------------------

    Array(data[:ledger_entries]).each_with_index do |entry_data, index|
      ledger_entry = voucher.ledger_entries.create!(
        position: entry_data[:position] || index,
        source_tag: entry_data[:source_tag],
        ledger_name: entry_data[:ledger_name],
        is_deemed_positive: entry_data[:is_deemed_positive],
        amount: entry_data[:amount]
      )

      persist_bill_allocations!(
        ledger_entry,
        entry_data[:bill_allocations]
      )

      persist_bank_allocations!(
        ledger_entry,
        entry_data[:bank_allocations]
      )

      persist_rate_details!(
        ledger_entry,
        entry_data[:rate_details]
      )
    end

    # ----------------------------------------------------------
    # Inventory entries
    # ----------------------------------------------------------

    Array(data[:inventory_entries]).each_with_index do |entry_data, index|
      inventory_entry = voucher.inventory_entries.create!(
        position: entry_data[:position] || index,
        source_tag: entry_data[:source_tag],
        stock_item_name: entry_data[:stock_item_name],
        is_deemed_positive: entry_data[:is_deemed_positive],
        actual_qty: entry_data[:actual_qty],
        billed_qty: entry_data[:billed_qty],
        rate: entry_data[:rate],
        amount: entry_data[:amount]
      )

      persist_batch_allocations!(
        inventory_entry,
        entry_data[:batch_allocations]
      )

      persist_accounting_allocations!(
        inventory_entry,
        entry_data[:accounting_allocations]
      )

      persist_rate_details!(
        inventory_entry,
        entry_data[:rate_details]
      )
    end

    voucher
  end

  # ============================================================
  # Bill allocations
  # ============================================================

  def persist_bill_allocations!(ledger_entry, allocations)
    Array(allocations).each_with_index do |allocation, index|
      ledger_entry.bill_allocations.create!(
        position: allocation[:position] || index,
        name: allocation[:name],
        bill_type: allocation[:bill_type],
        amount: allocation[:amount]
      )
    end
  end

  # ============================================================
  # Bank allocations
  # ============================================================

  def persist_bank_allocations!(ledger_entry, allocations)
    Array(allocations).each_with_index do |allocation, index|
      ledger_entry.bank_allocations.create!(
        position: allocation[:position] || index,
        date: allocation[:date],
        name: allocation[:name],
        transaction_type: allocation[:transaction_type],
        amount: allocation[:amount]
      )
    end
  end

  # ============================================================
  # Batch allocations
  # ============================================================

  def persist_batch_allocations!(inventory_entry, allocations)
    Array(allocations).each_with_index do |allocation, index|
      inventory_entry.batch_allocations.create!(
        position: allocation[:position] || index,
        godown_name: allocation[:godown_name],
        batch_name: allocation[:batch_name],
        actual_qty: allocation[:actual_qty],
        billed_qty: allocation[:billed_qty],
        amount: allocation[:amount]
      )
    end
  end

  # ============================================================
  # Accounting allocations
  # ============================================================

  def persist_accounting_allocations!(inventory_entry, allocations)
    Array(allocations).each_with_index do |allocation, index|
      accounting_allocation =
        inventory_entry.accounting_allocations.create!(
          position: allocation[:position] || index,
          ledger_name: allocation[:ledger_name],
          is_deemed_positive: allocation[:is_deemed_positive],
          amount: allocation[:amount]
        )

      persist_rate_details!(
        accounting_allocation,
        allocation[:rate_details]
      )
    end
  end

  # ============================================================
  # Rate details
  # ============================================================

  def persist_rate_details!(rateable, rate_details)
    Array(rate_details).each_with_index do |rate_detail, index|
      rateable.rate_details.create!(
        position: rate_detail[:position] || index,
        duty_head: rate_detail[:duty_head],
        rate: rate_detail[:rate]
      )
    end
  end

  # ============================================================
  # Import response
  # ============================================================

  def import_response(import, duplicate:)
    {
      importId: import.id,
      documentType: import.document_type,
      status: import.status,
      duplicate: duplicate,
      summary: import_summary(import)
    }
  end

  # ============================================================
  # Import details
  # ============================================================

  def import_details(import)
    {
      importId: import.id,
      documentType: import.document_type,
      status: import.status,
      contentHash: import.content_hash,
      detectedEncoding: import.detected_encoding,
      summary: import_summary(import),
      warnings: Array(import.warnings),
      error_messages: Array(import.error_messages)
    }
  end

  # ============================================================
  # Summary
  # ============================================================

  def import_summary(import)
    {
      vouchers: import.vouchers.count,

      ledgerEntries: LedgerEntry
        .joins(:voucher)
        .where(vouchers: { import_id: import.id })
        .count,

      inventoryEntries: InventoryEntry
        .joins(:voucher)
        .where(vouchers: { import_id: import.id })
        .count,

      warnings: Array(import.warnings).length,
      error_messages: Array(import.error_messages).length
    }
  end

  # ============================================================
  # Error response
  # ============================================================

  def render_error(code:, message:, status:)
    render json: {
      error: {
        code: code,
        message: message
      }
    }, status: status
  end
end