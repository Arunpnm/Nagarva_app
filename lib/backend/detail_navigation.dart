import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';

/// Opens Order Details for [o] with the same query parameters the Orders
/// list passes. Written once here so the redesigned Dashboard agenda rows
/// can open an order without a third hand-copied parameter block drifting
/// from the list's.
///
/// [hideCustomer] mirrors OrdersPage's supervisor masking on completed
/// orders — the detail page renders its own fallback for the hidden name.
void openOrderDetail(BuildContext context, OrdersRow o,
    {bool hideCustomer = false}) {
  context.pushNamed(
    OrderDetailPageWidget.routeName,
    queryParameters: {
      'orderId': serializeParam(o.id, ParamType.String),
      'orderCustomer': serializeParam(
          hideCustomer ? 'Customer (hidden)' : o.customer, ParamType.String),
      'orderPhone':
          serializeParam(hideCustomer ? null : o.phone, ParamType.String),
      'orderFromCity': serializeParam(o.fromCity, ParamType.String),
      'orderToCity': serializeParam(o.toCity, ParamType.String),
      'orderFromAddress': serializeParam(o.fromAddress, ParamType.String),
      'orderToAddress': serializeParam(o.toAddress, ParamType.String),
      'orderFromFloor':
          serializeParam(o.fromFloor?.toString(), ParamType.String),
      'orderToFloor': serializeParam(o.toFloor?.toString(), ParamType.String),
      'orderMoveDate':
          serializeParam(o.moveDateOrNull?.toString(), ParamType.String),
      'orderAmount': serializeParam(o.amount?.toString(), ParamType.String),
      'orderStatus': serializeParam(o.status, ParamType.String),
      'orderPaymentStatus': serializeParam(o.paymentStatus, ParamType.String),
      'orderTrackingStatus':
          serializeParam(o.trackingStatus, ParamType.String),
      'orderService': serializeParam(o.service, ParamType.String),
      'orderBranch': serializeParam(o.branch, ParamType.String),
      'orderType': serializeParam(o.orderType, ParamType.String),
      'orderNotes': serializeParam(o.notes, ParamType.String),
    }.withoutNulls,
  );
}

/// Opens Lead Details for [l] with the same query parameters the Leads
/// list passes. See [openOrderDetail] for why this exists.
void openLeadDetail(BuildContext context, LeadsRow l) {
  context.pushNamed(
    LeadDetailPageWidget.routeName,
    queryParameters: {
      'leadId': serializeParam(l.id, ParamType.String),
      'leadCustomer': serializeParam(l.customer, ParamType.String),
      'leadPhone': serializeParam(l.phone, ParamType.String),
      'leadEmail': serializeParam(l.email, ParamType.String),
      'leadFromCity': serializeParam(l.fromCity, ParamType.String),
      'leadToCity': serializeParam(l.toCity, ParamType.String),
      'leadApproxDate': serializeParam(l.approxDate, ParamType.String),
      'leadService': serializeParam(l.service, ParamType.String),
      'leadSource': serializeParam(l.source, ParamType.String),
      'leadStatus': serializeParam(l.status, ParamType.String),
      'leadBranch': serializeParam(l.branch, ParamType.String),
      'leadNotes': serializeParam(l.notes, ParamType.String),
    }.withoutNulls,
  );
}
