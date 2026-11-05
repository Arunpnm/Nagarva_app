import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '/app_session.dart';
import '/backend/fy_numbering.dart';
import '/backend/gst_state_codes.dart';
import '/backend/invoice_compliance.dart';
import '/backend/issued_documents.dart';
import '/backend/module_navigation.dart';
import '/backend/order_money.dart';
import '/backend/pricing_defaults.dart';
import '/backend/private_files.dart';
import '/backend/signature_service.dart';
import '/backend/supabase/org_scope.dart';
import '/backend/supabase/supabase.dart';
import '/backend/vendor_identity.dart';
import '/components/share_link_sheet.dart';
import '/components/invoice_pdf.dart';
import '/components/pdf_branding.dart';
import '/components/pdf_view_page.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/ng_tokens.dart';

import '/backend/edge_function_errors.dart';
/// Tax invoice generation for one order: Rule 46 check, the GST-rate
/// refusal, gapless numbering through `next_doc_number`, the inclusive
/// GST back-out and the branded PDF dialog.
///
/// Moved out of OrderDetailPage (30 Oct 2026) unchanged, so Order Details
/// and the order journey's Invoice stage run the same code — one copy of
/// the invoice rules, as CLAUDE.md requires for anything with money or
/// numbering in it. The order's customer, phone, cities and amount now
/// come from the order row read at generation time rather than from the
/// page's navigation parameters.
class InvoiceGenerator {
  InvoiceGenerator(
    this.context, {
    required this.orderId,
    this.hideCustomer = false,
    this.signature,
    this.onBusy,
  });

  final BuildContext context;
  final String orderId;
  final bool hideCustomer;
  final SignatureRequest? signature;

  /// Called with true once a number is about to be allocated and with
  /// false when generation ends, so the caller can disable its button.
  final void Function(bool busy)? onBusy;

  OrdersRow? _row;

  /// Set by generate(): the order's money under the shared rule, incl.
  /// extra charges that become invoice lines.
  OrderMoney? _money;

  String? get _orderAmount => _row?.amount?.toString();
  String? get _orderFromCity => _row?.fromCity;
  String? get _orderToCity => _row?.toCity;
  String? get _orderCustomer => _row?.customer;
  String? get _orderPhone => _row?.phone;

  /// Sequential invoice numbering. Order Details Session 1's brief is
  /// explicit: "Use next_doc_number for every document number. Do not
  /// roll your own counter" — migration 006's `number_series`/
  /// `next_doc_number(org, doc_type, branch, fy)` is atomic (row-locked)
  /// where the old mechanism this replaced was read-then-upsert against
  /// `settings` (ported from apc_webapp's own non-atomic
  /// DB.getNextInvoiceNo). Flagged for Arun: this starts a NEW series in
  /// `number_series` — it does not continue the old `inv_seq_<fy>` counter
  /// in `settings`, so the next invoice number restarts from 1 rather than
  /// picking up after the last one issued under the old mechanism.
  ///
  /// Session 3, task #46: `next_doc_number`'s return value already IS the
  /// full formatted number — `coalesce(prefix,'') || padded_n ||
  /// coalesce(suffix,'')` (migration 006's own function body). Migration
  /// 009 rewrote every org's `number_series.prefix` for these doc_types
  /// from the old `'INV-'`-style to a calendar-year `'2026/'`-style, to
  /// match APC's real `2026/0013` format — so the RPC alone now returns
  /// e.g. `'2026/0013'`. This method used to ALSO prepend
  /// `'$orgSlug/${currentFy()}/'` on top of that, which after 009 would
  /// have doubled up into `'APC/2526/2026/0013'`. Fixed: return the RPC's
  /// result as-is.
  Future<String> _nextInvoiceNo({String? branch}) async {
    return await allocateWithRollover(context, () async => await SupaFlow.client.rpc('next_doc_number', params: {
      'p_org': OrgScope.currentOrgId!,
      'p_doc_type': 'invoice',
      'p_branch': branch,
      'p_fy': currentFy(),
    }) as String);
  }

  /// The org exactly as the invoice will render it.
  ///
  /// Same dual-source resolution the PDF builder uses (organizations
  /// columns first, that org's `business_profile` jsonb as fallback), so
  /// the warning can never disagree with the document it is warning
  /// about — a check that reads a different source than the renderer is
  /// worse than no check.
  Future<OrgProfile> _resolveOrgProfile() async {
    Map<String, dynamic> profile = {};
    try {
      final rows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('key', 'business_profile'),
      );
      profile = rows.isEmpty ? {} : (rows.first.valueJson ?? {});
    } catch (_) {}
    OrganizationsRow? orgRow;
    try {
      final orgRows = await OrganizationsTable().queryRows(
        queryFn: (q) => q.eq('id', OrgScope.currentOrgId!),
      );
      if (orgRows.isNotEmpty) orgRow = orgRows.first;
    } catch (_) {}
    return OrgProfile.resolve(orgRow, businessProfile: profile);
  }

  /// Shows the most serious Rule 46 problem and returns true to continue.
  ///
  /// Only the FIRST issue is shown. Stacking four dialogs on someone
  /// trying to issue an invoice trains them to dismiss all of them, and
  /// `checkInvoiceCompliance` already orders by severity — a false GSTIN
  /// ahead of an unfinished profile.
  ///
  /// The action wording follows the KIND. "Issue anyway" is a reasonable
  /// thing to offer for an incomplete address; offering it in the same
  /// words for a GSTIN the vendor does not hold would make asserting a
  /// false registration a one-tap default. It still permits it — see
  /// _generateInvoice — but it names what is being done.
  Future<bool> _confirmInvoiceCompliance(InvoiceComplianceIssue issue) async {
    final ng = NgPalette.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(issue.title),
            content: SingleChildScrollView(
              child: Text(
                issue.message,
                style: NgFonts.geist(
                    fontSize: 13.5, color: ng.text),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(issue.isFalseDocument
                    ? 'Fix in Settings'
                    : 'Open Settings'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(issue.isFalseDocument
                    ? 'Issue with this GSTIN'
                    : 'Issue anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> generate() async {
    // Before a number is allocated — an invoice number is spent once and
    // the series must stay gapless, so the vendor decides BEFORE we burn
    // one, not after.
    try {
      final issues = checkInvoiceCompliance(await _resolveOrgProfile());
      if (issues.isNotEmpty && context.mounted) {
        final go = await _confirmInvoiceCompliance(issues.first);
        if (!go) {
          // openModule, not pushNamed — Settings is a module, and
          // pushNamed would stack a second app shell on top of this
          // one. See the navigation contract in CLAUDE.md.
          if (context.mounted) openModule(context, 'SettingsPage');
          return;
        }
      }
    } catch (_) {
      // A failed profile read must not stop a vendor invoicing. The check
      // is a courtesy; issuing the invoice is the job.
    }

    onBusy?.call(true);

    try {
      // Reuse the order's invoice_no if it already has one (one invoice
      // number per order, cached — matches the reference app).
      // LEAK_AUDIT.md leak #5 (Stage 1 fix): matched only on id before.
      final existing = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', orderId),
      );
      // §52 — a rate the product invents is a rate nobody chose. A null
      // quote_gst_pct means no person selected one, and an invoice is a
      // legal document, so this STOPS rather than substituting.
      //
      // Until 10 Sept 2026 the read below was `?? 5.0`. Checked against
      // live data that day: zero orders carry a null rate, so the fallback
      // had never fired — latent, not live. Recorded values are 0, 5 and
      // 18, and two orders are genuinely zero-rated through the "Charge
      // GST" switch. **Zero is a choice; null is the absence of one**, and
      // the two must not collapse into each other.
      //
      // This BLOCKS where the Rule 46 check above only warns, and the
      // difference is structural rather than a view about severity. Rule
      // 46 warns because the document is still issuable — a missing
      // address is a field the vendor can add afterwards. Here there is
      // nothing to proceed WITH: an "issue anyway" button would have to
      // pick a percentage, and picking one is the thing being prevented.
      // Substituting 18 instead of 5 would be a better guess that is
      // still a guess.
      //
      // Positioned before the allocation below so a refusal never burns a
      // number, and before the reuse branch too — that path issues a
      // document without allocating, and it must not carry an invented
      // rate either.
      if (existing.isEmpty || existing.first.quoteGstPct == null) {
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('GST rate was never set on this order'),
              content: Text(
                existing.isEmpty
                    ? 'This order could not be read, so its GST rate is '
                        'unknown. No invoice will be generated from a rate '
                        'nobody chose.'
                    : 'No GST rate has been chosen for this order, so there '
                        'is nothing to put on the invoice.\n\n'
                        'Set it on the order — Edit Order, then the Charge '
                        'GST switch — and generate again.\n\n'
                        'Zero is a valid choice and is not the same as '
                        'unset: turn Charge GST off to bill without GST.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      _row = existing.first;
      String invoiceNo;
      if (existing.isNotEmpty && (existing.first.invoiceNo ?? '').isNotEmpty) {
        invoiceNo = existing.first.invoiceNo!;
      } else {
        // Numbering-scheme decision (12 Aug 2026): one org-wide series per
        // doc type per FY, not per-branch. Under GST the invoice series
        // must be unique and gapless per registered person per FY —
        // per-branch series are for genuinely separate registrations, not
        // two branches under one GSTIN. branch: null always, now and
        // going forward; _nextInvoiceNo still accepts the parameter (kept
        // for a future tenant with real separate registrations), it's
        // just never passed a real value from here anymore.
        invoiceNo = await _nextInvoiceNo();
        // LEAK_AUDIT.md write-gap fix: matched only on id before.
        // invoice_issued_at stamped alongside invoice_no — same "once, at
        // first generation" convention as the number itself; a re-open of
        // an already-invoiced order reuses both rather than overwriting
        // the original date (see the `if` branch above).
        await OrdersTable().update(
          data: {
            'invoice_no': invoiceNo,
            'invoice_issued_at': DateTime.now().toUtc().toIso8601String(),
          },
          matchingRows: (q) => OrgScope.write(q).eq('id', orderId),
        );
      }

      final amount = double.tryParse(_orderAmount ?? '') ?? 0.0;
      // Fixed (RLS/numbering audit, 12 Aug 2026): was a hardcoded 5.0
      // unconditionally, ignoring orders.quote_gst_pct even when it held
      // the real quoted rate — confirmed live to have wrongly invoiced at
      // least one order (18% quoted, 5% billed).
      //
      // The `?? 5.0` that replaced it is gone too, 10 Sept 2026. Null is
      // refused above rather than defaulted, so by this line the rate is
      // always one a person actually chose. The old comment claimed "24 of
      // 25 live orders" carry no stored rate; the live data says zero do,
      // so that fallback was never the common path it was written for.
      final gstPct = existing.first.quoteGstPct!;
      final interstate =
          isInterState(_orderFromCity, _orderToCity);

      // GST IS INCLUSIVE IN `amount`, so the tax is BACKED OUT of the
      // total, not taken as a percentage OF it. Fixed 7 Sept 2026 after
      // Arun sent a real issued invoice (CBE/2026-27/0001) whose own
      // figures contradicted each other.
      //
      // The old line computed `amount * pct / 100` — a percentage of the
      // GST-INCLUSIVE total — and then subtracted that from the total to
      // get the taxable value. At 18% on Rs35,990 that printed:
      //     taxable Rs29,512, CGST Rs3,239, SGST Rs3,239
      // when the correct split is:
      //     taxable Rs30,500, CGST Rs2,745, SGST Rs2,745
      // The GRAND TOTAL was right either way, which is exactly why this
      // survived: the number the customer pays was never wrong. The
      // taxable value was understated by Rs988 and the tax overstated by
      // the same, on every invoice with a non-zero rate.
      //
      // It is not cosmetic. Those two figures are what GSTR-1 reports,
      // and the invoice contradicted ITSELF on its face: the particulars
      // summed to Rs30,500 — the correct taxable value — directly above a
      // "Taxable Value" line reading Rs29,512.
      //
      // base = total / (1 + pct/100); tax = total - base.
      //
      // 3 Nov 2026 (BUG-036 / BUG-044, Arun's rule of 2 Nov): the order's
      // money now comes from the shared OrderMoney rule. A quote-converted
      // order (GST inside the quote total) gives the same split as the
      // back-out above; a directly-booked order now gets GST ON TOP of
      // its amount instead of having it carved out of it; and the order's
      // extra charges are added as their own invoice lines.
      final money = await OrderMoney.load(_row!);
      _money = money;
      final baseAmount = money.taxable;
      final taxTotal = money.gstTotal;
      final invoiceTotal = money.total;
      if (amount <= 0 && invoiceTotal <= 0) {
        throw 'This order has no amount to invoice.';
      }
      final igst = interstate ? double.parse(taxTotal.toStringAsFixed(2)) : 0.0;
      final sgst = interstate
          ? 0.0
          : double.parse((taxTotal / 2).toStringAsFixed(2));
      final cgst = sgst;

      if (!context.mounted) return;
      _showInvoiceDialog(
        invoiceNo: invoiceNo,
        gstPct: gstPct,
        baseAmount: baseAmount,
        interstate: interstate,
        igst: igst,
        sgst: sgst,
        cgst: cgst,
        total: invoiceTotal,
        // Part 8 addendum item 3: lets _buildInvoicePdfBytes fall back to
        // the quote's signature when this order has none of its own yet.
        quotationId:
            existing.isNotEmpty ? existing.first.quotationId : null,
      );
      // Keep the issued copy even when nobody taps View / Print / Share
      // (5 Nov 2026). The number is issued above, but the PDF — and with it
      // the stored copy the customer's tracking page lists — was only built
      // by those buttons, so an invoice opened and closed was issued with
      // no copy: TEST-1002 showed "No documents yet" beside its invoice
      // number. Only when no copy exists yet, so the first issued copy is
      // never replaced by a regenerated one. Never awaited, never throws.
      _storeIssuedCopyIfMissing(
        invoiceNo: invoiceNo,
        gstPct: gstPct,
        baseAmount: baseAmount,
        interstate: interstate,
        igst: igst,
        sgst: sgst,
        cgst: cgst,
        total: invoiceTotal,
        quotationId:
            existing.isNotEmpty ? existing.first.quotationId : null,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate invoice: ${friendlyError(e)}')),
      );
    } finally {
      onBusy?.call(false);
    }
  }

  Future<void> _storeIssuedCopyIfMissing({
    required String invoiceNo,
    required double gstPct,
    required double baseAmount,
    required bool interstate,
    required double igst,
    required double sgst,
    required double cgst,
    required double total,
    String? quotationId,
  }) async {
    try {
      final List have = await OrgScope.read(
              SupaFlow.client.from('documents').select('id'))
          .eq('entity_type', 'order')
          .eq('entity_id', orderId)
          .eq('doc_type', 'invoice')
          .isFilter('deleted_at', null)
          .limit(1);
      if (have.isNotEmpty) return;
      // Builds the PDF; _buildInvoicePdfBytes stores it on the way out.
      await _buildInvoicePdfBytes(
        invoiceNo: invoiceNo,
        gstPct: gstPct,
        baseAmount: baseAmount,
        interstate: interstate,
        igst: igst,
        sgst: sgst,
        cgst: cgst,
        total: total,
        quotationId: quotationId,
      );
    } catch (_) {
      // Best-effort, like IssuedDocuments itself: the invoice is issued
      // either way, and View / Print / Share still store a copy.
    }
  }

  /// Fetches bytes for a public image URL (logo/signature). Best-effort:
  /// invoice generation never fails just because an image is missing.
  // Handles private-bucket references too (signature, BUG-013).
  Future<Uint8List?> _fetchBytes(String? url) => fetchFileBytes(url);

  /// Loads the vendor's business profile + branding saved on the Settings
  /// page (settings keys business_profile / signature_url, org logo_url)
  /// and builds the branded A4 PDF.
  Future<Uint8List> _buildInvoicePdfBytes({
    required String invoiceNo,
    required double gstPct,
    required double baseAmount,
    required bool interstate,
    required double igst,
    required double sgst,
    required double cgst,
    required double total,
    String? quotationId,
  }) async {
    Map<String, dynamic> profile = const {};
    String? signatureUrl;
    try {
      final rows = await SettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q)
            .inFilter('key', ['business_profile', 'signature_url']),
      );
      for (final r in rows) {
        if (r.key == 'business_profile') profile = r.valueJson ?? profile;
        if (r.key == 'signature_url') signatureUrl = r.value;
      }
    } catch (_) {}

    // Dual-source branding (Session 3, task #41): organizations columns
    // first, that same org's business_profile jsonb as fallback — see
    // OrgProfile.resolve's own doc comment.
    OrganizationsRow? orgRow;
    try {
      final orgRows = await OrganizationsTable().queryRows(
        queryFn: (q) => q.eq('id', OrgScope.currentOrgId!),
      );
      if (orgRows.isNotEmpty) orgRow = orgRows.first;
    } catch (_) {}
    final org = OrgProfile.resolve(orgRow,
        businessProfile: profile, legacyESignUrl: signatureUrl);

    DocumentBoilerplate boilerplate = const DocumentBoilerplate();
    try {
      final docRows = await AppSettingsTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('category', 'documents'),
      );
      boilerplate = DocumentBoilerplate.resolve(docRows);
    } catch (_) {}

    final logoBytes = await _fetchBytes(AppSession.instance.currentOrgLogoUrl);
    final signatureBytes = await _fetchBytes(org.signatoryImageUrl);

    // Tier A fields (field spec §3): Bill No/LR ref/Delivery Date/Vehicle
    // No/billing party/HSN/package+weight/payment remark/remark all live on
    // the order row itself (migration 009) — not carried in the page's nav
    // params, so re-queried here same as _generateInvoice already does for
    // invoice_no/quotation_id.
    OrdersRow? order;
    try {
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', orderId),
      );
      if (rows.isNotEmpty) order = rows.first;
    } catch (_) {}

    String? lrNo;
    int? packageCount;
    num? actualWeightKg;
    num? chargedWeightKg;
    String? gstPayableBy;
    if ((order?.lrId ?? '').isNotEmpty) {
      try {
        final lr = await SupaFlow.client
            .from('lr_register')
            .select('lr_no,package_count,actual_weight_kg,charged_weight_kg,'
                'gst_payable_by')
            .eq('id', order!.lrId!)
            .maybeSingle();
        if (lr != null) {
          lrNo = lr['lr_no'] as String?;
          packageCount = lr['package_count'] as int?;
          actualWeightKg = lr['actual_weight_kg'] as num?;
          chargedWeightKg = lr['charged_weight_kg'] as num?;
          final gpb = lr['gst_payable_by'] as String?;
          gstPayableBy = (gpb == null || gpb.isEmpty)
              ? null
              : gpb[0].toUpperCase() + gpb.substring(1);
        }
      } catch (_) {}
    }

    // Same charge heads the quotation shows (field spec §3: "Particulars
    // column same heads as quote") — only when this order has a linked
    // quote with a saved charges breakdown; otherwise InvoicePdf falls
    // back to a single freight line built from baseAmount.
    final particulars = <MapEntry<String, num>>[];
    if ((quotationId ?? '').isNotEmpty) {
      try {
        final qRows = await QuotationsTable().queryRows(
          queryFn: (q) => OrgScope.read(q).eq('id', quotationId!),
        );
        final charges = qRows.isNotEmpty ? qRows.first.charges : null;
        if (charges is Map) {
          final chargesMap = Map<String, dynamic>.from(charges);
          num amt(String key) {
            final v = chargesMap[key];
            if (v is num) return v;
            if (v is Map && v['amount'] is num) return v['amount'] as num;
            return num.tryParse('$v') ?? 0;
          }

          for (final f in kDefaultChargeFields) {
            if (f.key == 'discount' || f.key == 'advanceOnQuote') continue;
            final a = amt(f.key);
            if (a != 0) particulars.add(MapEntry(f.label, a));
          }
        }
      } catch (_) {}
    }
    // Extra charges as their own lines (Arun, 2 Nov 2026). When there is no
    // quote breakdown, the order's own base goes first so the lines still
    // add up to the taxable value.
    final extras = _money?.addons ?? const <OrderAddon>[];
    if (extras.isNotEmpty) {
      if (particulars.isEmpty) {
        particulars.add(MapEntry('Freight / Transport', _money!.base));
      }
      for (final a in extras) {
        particulars.add(MapEntry(a.description, a.amount));
      }
    }

    String? amountInWords;
    try {
      amountInWords = await SupaFlow.client
          .rpc('amount_in_words', params: {'amt': total}) as String?;
    } catch (_) {}

    // Item 3: embed the customer's e-signature once they've signed via
    // the public /sign link. Re-read rather than trusting the cached
    // _signature, so a PDF generated right after they sign isn't stale.
    SignatureRequest? sig = signature;
    try {
      sig = await SignatureService.find(
            documentType: 'invoice',
            documentId: orderId,
          ) ??
          sig;
    } catch (_) {}

    // Part 8 addendum item 3: an invoice-specific signature always takes
    // precedence if one was captured. Only when NONE exists does this fall
    // back to the quote's signature via the order's quotation_id — the
    // invoice signature-request button (Send for Signature, below) still
    // works exactly as before and, once used, permanently overrides this
    // fallback for this order.
    var inherited = false;
    if (!(sig?.isSigned ?? false) && (quotationId ?? '').isNotEmpty) {
      try {
        final quoteSig = await SignatureService.find(
          documentType: 'quote',
          documentId: quotationId!,
        );
        if (quoteSig?.isSigned ?? false) {
          sig = quoteSig;
          inherited = true;
        }
      } catch (_) {}
    }
    final quoteRef = (quotationId ?? '').length >= 8
        ? quotationId!.substring(0, 8).toUpperCase()
        : quotationId;

    final pdfBytes = await InvoicePdf.generate(
      customerSignatureBytes:
          (sig?.isSigned ?? false) ? sig!.signatureBytes : null,
      customerSignedByName: (sig?.isSigned ?? false) ? sig!.customerName : null,
      customerSignedByPhone:
          (sig?.isSigned ?? false) ? (hideCustomer ? null : _orderPhone) : null,
      customerSignedAt: (sig?.isSigned ?? false) ? sig!.signedAt : null,
      signatureInherited: inherited,
      inheritedFromQuoteRef: inherited ? quoteRef : null,
      invoiceNo: invoiceNo,
      gstPct: gstPct,
      org: org,
      boilerplate: boilerplate,
      customerName: hideCustomer
          ? 'Customer (hidden)'
          : (_orderCustomer ?? '—'),
      customerPhone: hideCustomer ? null : _orderPhone,
      fromCity: _orderFromCity,
      toCity: _orderToCity,
      fromAddress: order?.fromAddress,
      toAddress: order?.toAddress,
      baseAmount: baseAmount,
      interstate: interstate,
      igst: igst,
      cgst: cgst,
      sgst: sgst,
      total: total,
      logoBytes: logoBytes,
      signatureBytes: signatureBytes,
      lrNo: lrNo,
      deliveryDate: order?.deliveryDate,
      vehicleNo: order?.vehicleNo,
      billingPartyName: order?.billingPartyName,
      billingPartyGstin: order?.billingPartyGstin,
      billingPartyAddress: order?.billingPartyAddress,
      billingPartyPhone: order?.billingPartyPhone,
      packageCount: packageCount,
      actualWeightKg: actualWeightKg,
      chargedWeightKg: chargedWeightKg,
      hsnSacCode: (order?.hsnSacCode ?? '').isEmpty ? '996719' : order!.hsnSacCode!,
      paymentRemark: order?.paymentRemark,
      remark: order?.notes,
      particulars: particulars,
      gstPayableBy: gstPayableBy,
      reverseCharge: order?.reverseCharge ?? false,
      amountInWords: amountInWords,
      isPaid: order?.paymentStatus == 'paid',
    );

    // Keep the issued copy. Hooked HERE rather than at the Print and
    // Share buttons because both call this, and so will anything added
    // later - a hook per button is a hook someone forgets.
    //
    // Best-effort by design: a storage failure must never stop a vendor
    // handing an invoice to a customer standing in front of them. See
    // IssuedDocuments' own doc comment for why storing beats
    // regenerating regardless of the customer link.
    await IssuedDocuments.storeForOrder(
      orderId: orderId,
      docType: 'invoice',
      fileName: 'Invoice_${invoiceNo.replaceAll('/', '-')}.pdf',
      bytes: pdfBytes,
    );

    return pdfBytes;
  }

  void _showInvoiceDialog({
    required String invoiceNo,
    required double gstPct,
    required double baseAmount,
    required bool interstate,
    required double igst,
    required double sgst,
    required double cgst,
    required double total,
    String? quotationId,
  }) {
    final safeName = invoiceNo.replaceAll('/', '-');
    var busy = false;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Invoice $invoiceNo'),
          content: Text(
            busy
                ? 'Preparing PDF…'
                : 'Your tax invoice is ready. Download the PDF to share on '
                    'WhatsApp/email, or print it directly.',
          ),
          actions: [
            // VIEW first, because checking is what you do most.
            // Arun, 7 Sept 2026: "create view option so that we dont have
            // to download evertime then do correction". Every document
            // was download-or-print only, so proof-reading one meant a
            // file in Downloads per round, and no way to tell which of
            // them was current.
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() => busy = true);
                      final bytes = await _buildInvoicePdfBytes(
                        invoiceNo: invoiceNo,
                        gstPct: gstPct,
                        baseAmount: baseAmount,
                        interstate: interstate,
                        igst: igst,
                        sgst: sgst,
                        cgst: cgst,
                        total: total,
                        quotationId: quotationId,
                      );
                      if (!context.mounted) return;
                      setDialogState(() => busy = false);
                      await PdfViewPage.open(
                        context,
                        title: 'Invoice $invoiceNo',
                        bytes: bytes,
                        filename: 'Invoice_$safeName.pdf',
                      );
                    },
              child: const Text('View'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() => busy = true);
                      final bytes = await _buildInvoicePdfBytes(
                        invoiceNo: invoiceNo,
                        gstPct: gstPct,
                        baseAmount: baseAmount,
                        interstate: interstate,
                        igst: igst,
                        sgst: sgst,
                        cgst: cgst,
                        total: total,
                        quotationId: quotationId,
                      );
                      await Printing.layoutPdf(onLayout: (_) async => bytes);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
              child: const Text('Print'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() => busy = true);
                      final bytes = await _buildInvoicePdfBytes(
                        invoiceNo: invoiceNo,
                        gstPct: gstPct,
                        baseAmount: baseAmount,
                        interstate: interstate,
                        igst: igst,
                        sgst: sgst,
                        cgst: cgst,
                        total: total,
                        quotationId: quotationId,
                      );
                      // Browser download on web with a proper filename.
                      await Printing.sharePdf(
                          bytes: bytes,
                          filename: 'Invoice_$safeName.pdf');
                      // Job done — close the dialog instead of leaving the
                      // user staring at the same screen (Arun's feedback).
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Invoice_$safeName.pdf downloaded — check your Downloads bar.')),
                        );
                      }
                    },
              child: const Text('Download PDF'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }


  /// Sends the invoice for the customer's signature: refuses until the
  /// invoice exists, then shares the signing link. Returns the request
  /// (null when refused or failed). Moved from OrderDetailPage with
  /// [generate], for the same reason.
  Future<SignatureRequest?> sendForSignature(
      {String? customer, String? phone}) async {
    try {
      // THE INVOICE MUST EXIST FIRST. Arun's call, 7 Sept 2026, after
      // seeing the live page ask a customer to sign "invoice
      // ARUN-PACKERS-AND-COURIERS-1002" - an ORDER id, on an order with
      // no invoice, with no amount shown anywhere.
      //
      // A signature is evidence in a dispute months later. One taken
      // before the document exists evidences that somebody drew a
      // squiggle, not what they agreed to - and once the invoice IS
      // generated it carries a different number entirely, so the signed
      // record and the document name different things.
      //
      // This removes nothing: a QUOTE signature (Lead Details -> Send for
      // Signature) is the pre-invoice acceptance path and is untouched.
      final rows = await OrdersTable().queryRows(
        queryFn: (q) => OrgScope.read(q).eq('id', orderId),
      );
      final invoiceNo =
          rows.isNotEmpty ? (rows.first.invoiceNo ?? '') : '';
      if (invoiceNo.trim().isEmpty) {
        if (!context.mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Generate the invoice first — the customer signs the '
              'invoice, so it has to exist before the link is sent.'),
          duration: Duration(seconds: 5),
        ));
        return null;
      }

      final sig = await SignatureService.getOrCreate(
        documentType: 'invoice',
        documentId: orderId,
        // document_id stays the ORDER id: it is the stable lookup key
        // `find()` matches on, so it must not change when the invoice is
        // later generated, or a second signature request would be minted
        // for a document the customer has already signed.
        orderId: orderId,
        customerName: customer,
      );
      if (!context.mounted) return sig;
      final org = VendorIdentity.forSentence;
      await ShareLinkSheet.show(
        context,
        title: sig.isSigned ? 'Already signed' : 'Send for signature',
        subtitle: sig.isSigned
            ? 'Signed by ${sig.customerName ?? 'the customer'}'
                '${sig.signedAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(sig.signedAt!.toLocal())}'}.'
                ' The link still opens a read-only copy.'
            : 'The customer opens this link, reviews the invoice and signs '
                'on their phone. No login needed.',
        link: sig.link,
        phone: phone,
        message: 'Hello${customer == null ? '' : ' $customer'}, '
            'please review and accept your invoice from $org:',
      );
      return sig;
    } catch (e) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create signature link: ${friendlyError(e)}')),
      );
      return null;
    }
  }
}
