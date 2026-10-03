# app/serializers/tally/voucher_serializer.rb

module Tally
  class VoucherSerializer
    def initialize(voucher)
      @voucher = voucher
    end

    def as_json
      {
        id: @voucher.id,
        voucherIndex: @voucher.voucher_index,
        date: @voucher.date,
        voucherType: @voucher.voucher_type,
        voucherNumber: @voucher.voucher_number,
        partyLedgerName: @voucher.party_ledger_name,
        narration: @voucher.narration,
        xmlAttributes: @voucher.xml_attributes || {},
        warnings: @voucher.warnings || [],

        ledgerEntries: serialize_ledger_entries,
        inventoryEntries: serialize_inventory_entries
      }
    end

    private

    def serialize_ledger_entries
      @voucher.ledger_entries.map do |entry|
        {
          id: entry.id,
          ledgerName: entry.ledger_name,
          isDeemedPositive: entry.is_deemed_positive,
          amount: entry.amount,
          xmlAttributes: entry.xml_attributes || {},

          billAllocations: entry.bill_allocations.map do |allocation|
            {
              id: allocation.id,
              name: allocation.name,
              billType: allocation.bill_type,
              amount: allocation.amount,
              xmlAttributes: allocation.xml_attributes || {}
            }
          end,

          bankAllocations: entry.bank_allocations.map do |allocation|
            {
              id: allocation.id,
              date: allocation.date,
              name: allocation.name,
              transactionType: allocation.transaction_type,
              amount: allocation.amount,
              xmlAttributes: allocation.xml_attributes || {}
            }
          end,

          rateDetails: serialize_rate_details(entry)
        }
      end
    end

    def serialize_inventory_entries
      @voucher.inventory_entries.map do |entry|
        {
          id: entry.id,
          stockItemName: entry.stock_item_name,
          quantity: entry.quantity,
          rate: entry.rate,
          amount: entry.amount,
          xmlAttributes: entry.xml_attributes || {},

          batchAllocations: entry.batch_allocations.map do |allocation|
            {
              id: allocation.id,
              batchName: allocation.batch_name,
              destinationGodownName: allocation.destination_godown_name,
              quantity: allocation.quantity,
              rate: allocation.rate,
              amount: allocation.amount,
              xmlAttributes: allocation.xml_attributes || {}
            }
          end,

          accountingAllocations: entry.accounting_allocations.map do |allocation|
            {
              id: allocation.id,
              ledgerName: allocation.ledger_name,
              amount: allocation.amount,
              xmlAttributes: allocation.xml_attributes || {},

              rateDetails: serialize_rate_details(allocation)
            }
          end,

          rateDetails: serialize_rate_details(entry)
        }
      end
    end

    def serialize_rate_details(record)
      return [] unless record.respond_to?(:rate_details)

      record.rate_details.map do |rate|
        {
          id: rate.id,
          quantity: rate.quantity,
          rate: rate.rate,
          amount: rate.amount,
          xmlAttributes: rate.xml_attributes || {}
        }
      end
    end
  end
end