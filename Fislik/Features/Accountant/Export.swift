import Foundation
import UIKit
import zlib

/// Columns of the accountant export (mirrors fislik-web `receiptReview.ts`).
enum ExportColumn: String, CaseIterable, Identifiable {
    case date = "Tarih", seller = "Satıcı", taxId = "VKN/TCKN", taxOffice = "Vergi Dairesi", number = "Fiş No"
    case docType = "Belge Türü", total = "Toplam", vatTotal = "KDV Toplam", vat1 = "KDV %1", vat10 = "KDV %10", vat20 = "KDV %20"
    case payment = "Ödeme", category = "Kategori", analysis = "Analiz", processed = "İşlendi"

    var id: String { rawValue }

    static let defaults: [ExportColumn] = allCases.filter { $0 != .analysis && $0 != .processed }

    var isNumeric: Bool { [.total, .vatTotal, .vat1, .vat10, .vat20].contains(self) }

    /// Raw cell value: Decimal for numeric columns, String otherwise.
    func value(_ r: Receipt) -> Any {
        let e = r.extraction
        func vat(_ rate: Int) -> Decimal { e?.vatBreakdown.filter { $0.rate == rate }.reduce(0) { $0 + $1.amount } ?? 0 }
        switch self {
        case .date: return e?.receiptDate.map(TR.dotted) ?? ""
        case .seller: return e?.merchantLegalName ?? e?.merchantName ?? ""
        case .taxId: return e?.merchantTaxId ?? ""
        case .taxOffice: return e?.merchantTaxOffice ?? ""
        case .number: return e?.receiptNumber ?? ""
        case .docType: return e?.docType?.label ?? ""
        case .total: return e?.totalAmount ?? 0
        case .vatTotal: return e?.vatTotal ?? 0
        case .vat1: return vat(1)
        case .vat10: return vat(10)
        case .vat20: return vat(20)
        case .payment: return e?.paymentMethod?.label ?? ""
        case .category: return e?.expenseCategory?.label ?? ""
        case .analysis: return r.isQueued ? "Sırada" : e?.status == .done ? (e?.edited == true ? "Elle doğrulandı" : "Tamam") : e?.status == .failed ? "Okunamadı" : "Bekliyor"
        case .processed: return r.processed ? "Evet" : "Hayır"
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case excel, csv, pdf, zip
    var id: String { rawValue }
    var ext: String { self == .excel ? "xlsx" : rawValue }
}

enum Exporter {
    static func filename(client: String, period: Period, format: ExportFormat) -> String {
        "\(client.slug)-\(period.raw).\(format.ext)"
    }

    static func csv(_ receipts: [Receipt], columns: [ExportColumn]) -> Data {
        func esc(_ s: String) -> String {
            s.contains(";") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var lines = [columns.map(\.rawValue).joined(separator: ";")]
        for r in receipts {
            lines.append(columns.map { c in
                let v = c.value(r)
                if let d = v as? Decimal { return TR.plain(d).replacingOccurrences(of: ".", with: "") }
                return esc("\(v)")
            }.joined(separator: ";"))
        }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n")).utf8)
    }

    // MARK: XLSX (minimal SpreadsheetML in a stored ZIP)

    static func xlsx(_ receipts: [Receipt], columns: [ExportColumn], sheetName: String) -> Data {
        func xml(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func colName(_ i: Int) -> String {
            var n = i + 1, s = ""
            while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(65 + r)!) + s; n = (n - 1) / 26 }
            return s
        }
        var rows = "<row r=\"1\">" + columns.enumerated().map { i, c in "<c r=\"\(colName(i))1\" t=\"inlineStr\" s=\"1\"><is><t>\(xml(c.rawValue))</t></is></c>" }.joined() + "</row>"
        for (ri, r) in receipts.enumerated() {
            let rn = ri + 2
            rows += "<row r=\"\(rn)\">"
            for (ci, c) in columns.enumerated() {
                let ref = "\(colName(ci))\(rn)"
                let v = c.value(r)
                if let d = v as? Decimal {
                    rows += "<c r=\"\(ref)\" s=\"2\"><v>\(NSDecimalNumber(decimal: d).stringValue)</v></c>"
                } else {
                    rows += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(xml("\(v)"))</t></is></c>"
                }
            }
            rows += "</row>"
        }
        let widths = columns.enumerated().map { i, c in "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(c == .seller ? 32 : c.isNumeric ? 13 : 16)\" customWidth=\"1\"/>" }.joined()
        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>\(widths)</cols><sheetData>\(rows)</sheetData></worksheet>
        """
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="3"><xf/><xf fontId="1" applyFont="1"/><xf numFmtId="164" applyNumberFormat="1"/></cellXfs></styleSheet>
        """
        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="\(xml(String(sheetName.prefix(31))))" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
        let files: [(String, String)] = [
            ("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
            """),
            ("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """),
            ("xl/workbook.xml", workbook),
            ("xl/_rels/workbook.xml.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
            """),
            ("xl/worksheets/sheet1.xml", sheet),
            ("xl/styles.xml", styles),
        ]
        return ZipWriter.stored(files.map { ($0.0, Data($0.1.utf8)) })
    }

    // MARK: PDF

    static func pdf(_ receipts: [Receipt], columns: [ExportColumn], title: String, subtitle: String) -> Data {
        let page = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 landscape
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let font = UIFont(name: "PlusJakartaSans-Regular", size: 7.5) ?? .systemFont(ofSize: 7.5)
        let bold = UIFont(name: "PlusJakartaSans-Bold", size: 7.5) ?? .boldSystemFont(ofSize: 7.5)
        let margin: CGFloat = 28
        let width = page.width - margin * 2
        let weights = columns.map { $0 == .seller ? 2.4 : $0.isNumeric ? 1.0 : 1.2 }
        let unit = width / CGFloat(weights.reduce(0, +))
        let rowH: CGFloat = 16

        return renderer.pdfData { ctx in
            var y: CGFloat = 0
            func newPage() {
                ctx.beginPage()
                (title as NSString).draw(at: CGPoint(x: margin, y: margin), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15)])
                (subtitle as NSString).draw(at: CGPoint(x: margin, y: margin + 20), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
                y = margin + 44
                drawRow(columns.map(\.rawValue), font: bold, fill: UIColor(white: 0.93, alpha: 1))
            }
            func drawRow(_ values: [String], font: UIFont, fill: UIColor? = nil) {
                if let fill { fill.setFill(); UIRectFill(CGRect(x: margin, y: y, width: width, height: rowH)) }
                var x = margin
                for (i, v) in values.enumerated() {
                    let w = unit * CGFloat(weights[i])
                    let style = NSMutableParagraphStyle()
                    style.alignment = columns[i].isNumeric ? .right : .left
                    style.lineBreakMode = .byTruncatingTail
                    (v as NSString).draw(in: CGRect(x: x + 3, y: y + 4, width: w - 6, height: rowH - 4), withAttributes: [.font: font, .paragraphStyle: style])
                    x += w
                }
                UIColor(white: 0.85, alpha: 1).setFill()
                UIRectFill(CGRect(x: margin, y: y + rowH - 0.5, width: width, height: 0.5))
                y += rowH
            }
            newPage()
            for r in receipts {
                if y + rowH > page.height - margin { newPage() }
                drawRow(columns.map { c in
                    let v = c.value(r)
                    return (v as? Decimal).map(TR.plain) ?? "\(v)"
                }, font: font)
            }
            if y + rowH > page.height - margin { newPage() }
            let totals = columns.map { c -> String in
                guard c.isNumeric else { return c == columns.first ? "TOPLAM" : "" }
                return TR.plain(receipts.reduce(Decimal(0)) { $0 + ((c.value($1) as? Decimal) ?? 0) })
            }
            drawRow(totals, font: bold, fill: UIColor(white: 0.96, alpha: 1))
        }
    }
}

/// Tiny ZIP writer (stored, no compression) — enough for XLSX packages.
enum ZipWriter {
    static func stored(_ files: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        for (name, data) in files {
            let nameData = Data(name.utf8)
            let crc = data.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))) }
            let offset = UInt32(out.count)
            var local = Data([0x50, 0x4B, 0x03, 0x04])
            local += le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            local += le32(crc) + le32(UInt32(data.count)) + le32(UInt32(data.count))
            local += le16(nameData.count) + le16(0) + nameData
            out += local + data
            var entry = Data([0x50, 0x4B, 0x01, 0x02])
            entry += le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            entry += le32(crc) + le32(UInt32(data.count)) + le32(UInt32(data.count))
            entry += le16(nameData.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + nameData
            central += entry
        }
        let centralOffset = UInt32(out.count)
        out += central
        var end = Data([0x50, 0x4B, 0x05, 0x06])
        end += le16(0) + le16(0) + le16(files.count) + le16(files.count)
        end += le32(UInt32(central.count)) + le32(centralOffset) + le16(0)
        return out + end
    }
}
