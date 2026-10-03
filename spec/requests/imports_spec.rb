require "rails_helper"
RSpec.describe "Tally Imports API", type: :request do
  def json_response
    JSON.parse(response.body)
  end
  def upload_file(content, filename = "test.xml")
    Rack::Test::UploadedFile.new(
      StringIO.new(content),
      "application/xml",
      original_filename: filename
    )
  end
  let(:valid_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <ENVELOPE>
        <HEADER>
          <VERSION>1</VERSION>
          <STATUS>1</STATUS>
        </HEADER>
        <BODY>
          <DATA>
            <COLLECTION>
              <VOUCHER VCHTYPE="Receipt" ACTION="Create">
                <DATE>20260715</DATE>
                <VOUCHERTYPENAME>Receipt</VOUCHERTYPENAME>
                <VOUCHERNUMBER>RCP-001</VOUCHERNUMBER>
                <PARTYLEDGERNAME>Demo Customer</PARTYLEDGERNAME>
                <NARRATION>Test receipt</NARRATION>
                <ALLLEDGERENTRIES.LIST>
                  <LEDGERNAME>Demo Bank</LEDGERNAME>
                  <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>
                  <AMOUNT>1250.00</AMOUNT>
                  <BANKALLOCATIONS.LIST>
                    <DATE>20260715</DATE>
                    <NAME>UTR-001</NAME>
                    <TRANSACTIONTYPE>Inter Bank Transfer</TRANSACTIONTYPE>
                    <AMOUNT>1250.00</AMOUNT>
                  </BANKALLOCATIONS.LIST>
                </ALLLEDGERENTRIES.LIST>
                <ALLLEDGERENTRIES.LIST>
                  <LEDGERNAME>Demo Customer</LEDGERNAME>
                  <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>
                  <AMOUNT>-1250.00</AMOUNT>
                  <BILLALLOCATIONS.LIST>
                    <NAME>INV-001</NAME>
                    <BILLTYPE>Agst Ref</BILLTYPE>
                    <AMOUNT>-1250.00</AMOUNT>
                  </BILLALLOCATIONS.LIST>
                </ALLLEDGERENTRIES.LIST>
              </VOUCHER>
            </COLLECTION>
          </DATA>
        </BODY>
      </ENVELOPE>
    XML
  end
  let(:response_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <RESPONSE>
        <CREATED>0</CREATED>
        <ALTERED>0</ALTERED>
        <DELETED>0</DELETED>
        <IGNORED>1</IGNORED>
        <ERRORS>1</ERRORS>
        <LINEERROR>Demo ledger does not exist</LINEERROR>
      </RESPONSE>
    XML
  end
  describe "POST /imports" do
    it "imports a valid XML file" do
      # debugger
      post "/imports",
           params: {
             file: upload_file(
               valid_xml,
               "receipt.xml"
             )
           }
      expect(response).to have_http_status(:created)
      body = json_response
      expect(body["importId"]).to be_present
      expect(body["documentType"]).to eq("voucherExport")
      expect(body["status"]).to eq("completed")
      expect(body["duplicate"]).to eq(false)
    end
    it "stores the uploaded XML" do
      expect {
        post "/imports",
             params: {
               file: upload_file(
                 valid_xml,
                 "receipt.xml"
               )
             }
      }.to change(Import, :count).by(1)
      import = Import.last
      expect(import.raw_source).to include("<ENVELOPE>")
    end
    it "detects UTF-8 encoding" do
      post "/imports",
           params: {
             file: upload_file(
               valid_xml,
               "receipt.xml"
             )
           }
      import = Import.last
      expect(import.detected_encoding).to eq("UTF-8")
    end
    it "creates the voucher" do
      expect {
        post "/imports",
             params: {
               file: upload_file(
                 valid_xml,
                 "receipt.xml"
               )
             }
      }.to change(Voucher, :count).by(1)
      voucher = Voucher.last
      expect(voucher.voucher_number).to eq("RCP-001")
    end
    it "returns an error when file is missing" do
      post "/imports"
      expect(response).to have_http_status(:bad_request)
      expect(json_response.dig("error", "code"))
        .to eq("FILE_REQUIRED")
      expect(json_response.dig("error", "message"))
        .to eq("multipart field 'file' is required")
    end
    it "returns an error when file is empty" do
      post "/imports",
           params: {
             file: upload_file("", "empty.xml")
           }
      expect(response).to have_http_status(:bad_request)
      expect(json_response.dig("error", "code"))
        .to eq("EMPTY_FILE")
      expect(json_response.dig("error", "message"))
        .to eq("Uploaded file is empty")
    end
    it "returns an error for invalid XML" do
      invalid_xml = "<ENVELOPE><BROKEN></ENVELOPE>"
      post "/imports",
           params: {
             file: upload_file(
               invalid_xml,
               "invalid.xml"
             )
           }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response.dig("error", "code"))
        .to eq("INVALID_XML")
    end
    it "returns an error for unsupported document" do
      unsupported_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <UNKNOWN>
          <DATA>Test</DATA>
        </UNKNOWN>
      XML
      post "/imports",
           params: {
             file: upload_file(
               unsupported_xml,
               "unknown.xml"
             )
           }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response.dig("error", "code"))
        .to eq("UNSUPPORTED_DOCUMENT")
    end
    it "returns an error for invalid encoding" do
      allow_any_instance_of(Tally::XmlImporter)
        .to receive(:detect_encoding)
        .and_return("INVALID")
      post "/imports",
           params: {
             file: upload_file(
               valid_xml,
               "invalid_encoding.xml"
             )
           }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response.dig("error", "code"))
        .to eq("INVALID_ENCODING")
    end
    it "returns an error when file is too large" do
      allow_any_instance_of(Tally::XmlImporter)
        .to receive(:validate_file_size!)
        .and_raise(
          Tally::XmlImporter::FileTooLargeError,
          "Uploaded file exceeds the maximum allowed size"
        )
      post "/imports",
           params: {
             file: upload_file(
               valid_xml,
               "large.xml"
             )
           }
      expect(response).to have_http_status(:payload_too_large)
      expect(json_response.dig("error", "code"))
        .to eq("FILE_TOO_LARGE")
    end
    it "returns duplicate for the same file" do
      file_content = valid_xml
      post "/imports",
           params: {
             file: upload_file(
               file_content,
               "first.xml"
             )
           }
      expect(response).to have_http_status(:created)
      first_import_id = json_response["importId"]
      post "/imports",
           params: {
             file: upload_file(
               file_content,
               "second.xml"
             )
           }
      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body["duplicate"]).to eq(true)
      expect(body["importId"]).to eq(first_import_id)
    end
    it "detects duplicate even when filename changes" do
      post "/imports",
           params: {
             file: upload_file(
               valid_xml,
               "first.xml"
             )
           }
      first_import_id = json_response["importId"]
      post "/imports",
           params: {
             file: upload_file(
               valid_xml,
               "completely-different-name.xml"
             )
           }
      expect(response).to have_http_status(:ok)
      expect(json_response["duplicate"]).to eq(true)
      expect(json_response["importId"])
        .to eq(first_import_id)
    end
    it "creates a new import for different content" do
      post "/imports",
           params: {
             file: upload_file(
               valid_xml,
               "first.xml"
             )
           }
      first_import_id = json_response["importId"]
      different_xml = valid_xml.sub(
        "RCP-001",
        "RCP-002"
      )
      post "/imports",
           params: {
             file: upload_file(
               different_xml,
               "second.xml"
             )
           }
      expect(response).to have_http_status(:created)
      expect(json_response["duplicate"])
        .to eq(false)
      expect(json_response["importId"])
        .not_to eq(first_import_id)
    end
    it "imports a Tally RESPONSE document" do
      post "/imports",
           params: {
             file: upload_file(
               response_xml,
               "response.xml"
             )
           }
      expect(response).to have_http_status(:created)
      body = json_response
      expect(body["documentType"])
        .to eq("tallyResponse")
    end
  end
  describe "GET /imports/:id" do
    let!(:import) do
      Import.create!(
        content_hash: Digest::SHA256.hexdigest(valid_xml),
        document_type: "voucherExport",
        status: "completed",
        detected_encoding: "UTF-8",
        warnings: [],
        error_messages: [],
        raw_source: valid_xml
      )
    end
    it "returns import details" do
      get "/imports/#{import.id}"
      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body["importId"].to_s)
        .to eq(import.id.to_s)
      expect(body["documentType"])
        .to eq("voucherExport")
      expect(body["status"])
        .to eq("completed")
      expect(body["detectedEncoding"])
        .to eq("UTF-8")
    end
    it "returns content hash" do
      get "/imports/#{import.id}"
      expect(json_response["contentHash"])
        .to eq(import.content_hash)
    end
    it "returns warnings and errors" do
      get "/imports/#{import.id}"
      # debugger
      expect(json_response["warnings"])
        .to eq([])
      expect(json_response["errors"])
        .to eq(nil)
    end
    it "returns 404 when import does not exist" do
      get "/imports/999999"
      expect(response).to have_http_status(:not_found)
      expect(json_response.dig("error", "code"))
        .to eq("IMPORT_NOT_FOUND")
      expect(json_response.dig("error", "message"))
        .to eq("Import not found")
    end
  end
  describe "GET /imports/:id/vouchers" do
    let!(:import) do
      Import.create!(
        content_hash: Digest::SHA256.hexdigest(
          valid_xml + "voucher"
        ),
        document_type: "voucherExport",
        status: "completed",
        detected_encoding: "UTF-8",
        warnings: [],
        error_messages: [],
        raw_source: valid_xml
      )
    end
    it "returns vouchers for the import" do
      voucher = import.vouchers.create!(
        voucher_index: 0,
        date: "20260715",
        voucher_type: "Receipt",
        voucher_number: "RCP-001",
        party_ledger_name: "Demo Customer",
        narration: "Test receipt",
        xml_attributes: {
          "VCHTYPE" => "Receipt",
          "ACTION" => "Create"
        },
        warnings: []
      )
      get "/imports/#{import.id}/vouchers"
      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body["count"]).to eq(1)
      expect(body["items"]).to be_an(Array)
    end
    it "returns empty items when import has no vouchers" do
      get "/imports/#{import.id}/vouchers"
      expect(response).to have_http_status(:ok)
      expect(json_response["items"])
        .to eq([])
      expect(json_response["count"])
        .to eq(0)
    end
    it "returns 404 when import does not exist" do
      get "/imports/999999/vouchers"
      expect(response).to have_http_status(:not_found)
      expect(json_response.dig("error", "code"))
        .to eq("IMPORT_NOT_FOUND")
      expect(json_response.dig("error", "message"))
        .to eq("Import not found")
    end
  end
end