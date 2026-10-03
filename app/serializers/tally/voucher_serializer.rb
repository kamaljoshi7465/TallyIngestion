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
          position: entry.position,
          sourceTag: entry.source_tag,
          ledgerName: entry.ledger_name,
          isDeemedPositive: entry.is_deemed_positive,
          amount: entry.amount,

          billAllocations: entry.bill_allocations.map do |allocation|
            {
              id: allocation.id,
              position: allocation.position,
              name: allocation.name,
              billType: allocation.bill_type,
              amount: allocation.amount
            }
          end,

          bankAllocations: entry.bank_allocations.map do |allocation|
            {
              id: allocation.id,
              position: allocation.position,
              date: allocation.date,
              name: allocation.name,
              transactionType: allocation.transaction_type,
              amount: allocation.amount
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
          position: entry.position,
          sourceTag: entry.source_tag,
          stockItemName: entry.stock_item_name,
          isDeemedPositive: entry.is_deemed_positive,
          actualQty: entry.actual_qty,
          billedQty: entry.billed_qty,
          rate: entry.rate,
          amount: entry.amount,

          batchAllocations: entry.batch_allocations.map do |allocation|
            {
              id: allocation.id,
              position: allocation.position,
              godownName: allocation.godown_name,
              batchName: allocation.batch_name,
              actualQty: allocation.actual_qty,
              billedQty: allocation.billed_qty,
              amount: allocation.amount
            }
          end,

          accountingAllocations: entry.accounting_allocations.map do |allocation|
            {
              id: allocation.id,
              position: allocation.position,
              ledgerName: allocation.ledger_name,
              isDeemedPositive: allocation.is_deemed_positive,
              amount: allocation.amount,

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
          position: rate.position,
          dutyHead: rate.duty_head,
          rate: rate.rate
        }
      end
    end
  end
end