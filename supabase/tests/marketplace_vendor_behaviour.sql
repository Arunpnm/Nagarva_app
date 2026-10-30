-- Behaviour checks for 20261030_marketplace_vendor.sql; see marketplace_vendor_stubs.sql.
-- Each '---' line says what should happen. Tier timing, masking, first accept wins,
-- step order, photos, delivery code, wallet maths, withdrawal floor, refusals.
\set ON_ERROR_STOP 0
-- ids
insert into organizations values ('aaaaaaaa-0000-0000-0000-000000000001','Gold Movers'),('aaaaaaaa-0000-0000-0000-000000000002','Silver Movers'),('aaaaaaaa-0000-0000-0000-000000000003','Bronze Movers'),('aaaaaaaa-0000-0000-0000-000000000004','No City');
insert into org_members values
 ('aaaaaaaa-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001','owner'),
 ('aaaaaaaa-0000-0000-0000-000000000002','11111111-0000-0000-0000-000000000002','owner'),
 ('aaaaaaaa-0000-0000-0000-000000000003','11111111-0000-0000-0000-000000000003','owner'),
 ('aaaaaaaa-0000-0000-0000-000000000004','11111111-0000-0000-0000-000000000004','owner'),
 ('aaaaaaaa-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000009','staff');
insert into platform_admins(user_id) values ('99999999-0000-0000-0000-000000000001');
insert into mkt_vendors(org_id,available,home_city,score) values
 ('aaaaaaaa-0000-0000-0000-000000000001',true,'Chennai',85),
 ('aaaaaaaa-0000-0000-0000-000000000002',true,'Chennai',65),
 ('aaaaaaaa-0000-0000-0000-000000000003',true,'Chennai',40),
 ('aaaaaaaa-0000-0000-0000-000000000004',true,null,95);
insert into mkt_jobs(id,job_no,pickup_city,drop_city,package,move_date,total_inr,gst_inr,advance_inr,commission_pct,customer_name,customer_phone,delivery_otp) values
 ('bbbbbbbb-0000-0000-0000-000000000001','NJ-1','Chennai','Porur','standard','2026-11-05',11800,1800,1180,12,'Karthik','9840000000','4321'),
 ('bbbbbbbb-0000-0000-0000-000000000002','NJ-2','Chennai','Bengaluru','premium','2026-11-06',59000,9000,5900,12,'Priya','9840000001','1111');

set role authenticated;
\echo '--- 1. anonymous caller refused'
set test.uid = '';
select count(*) from mkt_vendor_jobs('aaaaaaaa-0000-0000-0000-000000000001');
\echo '--- 2. wallet 0 < min 2000: gold sees nothing'
set test.uid = '11111111-0000-0000-0000-000000000001';
select count(*) as gold_sees from mkt_vendor_jobs('aaaaaaaa-0000-0000-0000-000000000001');
reset role;
insert into mkt_wallet_entries(org_id,kind,amount,status) select id,'topup',3000,'done' from organizations;
set role authenticated;
\echo '--- 3. just broadcast: gold sees 2, silver 0, bronze 0, no-city 0'
set test.uid = '11111111-0000-0000-0000-000000000001'; select count(*) gold from mkt_vendor_jobs('aaaaaaaa-0000-0000-0000-000000000001');
set test.uid = '11111111-0000-0000-0000-000000000002'; select count(*) silver from mkt_vendor_jobs('aaaaaaaa-0000-0000-0000-000000000002');
set test.uid = '11111111-0000-0000-0000-000000000003'; select count(*) bronze from mkt_vendor_jobs('aaaaaaaa-0000-0000-0000-000000000003');
set test.uid = '11111111-0000-0000-0000-000000000004'; select count(*) nocity from mkt_vendor_jobs('aaaaaaaa-0000-0000-0000-000000000004');
reset role; update mkt_jobs set broadcast_at = now() - interval '6 minutes'; set role authenticated;
\echo '--- 4. after 6 min: silver sees 1 (premium is gold only), bronze 0'
set test.uid = '11111111-0000-0000-0000-000000000002'; select count(*) silver, string_agg(job_no,',') from mkt_vendor_jobs('aaaaaaaa-0000-0000-0000-000000000002');
set test.uid = '11111111-0000-0000-0000-000000000003'; select count(*) bronze from mkt_vendor_jobs('aaaaaaaa-0000-0000-0000-000000000003');
reset role; update mkt_jobs set broadcast_at = now() - interval '16 minutes'; set role authenticated;
\echo '--- 5. after 16 min: bronze sees 1, customer masked'
set test.uid = '11111111-0000-0000-0000-000000000003'; select job_no, customer_name, customer_phone, mine from mkt_vendor_jobs('aaaaaaaa-0000-0000-0000-000000000003');
\echo '--- 6. direct select on mkt_jobs as a vendor: 0 rows'
select count(*) from mkt_jobs;
\echo '--- 7. staff (not manager) of gold org refused'
set test.uid = '11111111-0000-0000-0000-000000000009'; select mkt_accept_job('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001');
\echo '--- 8. silver accepts NJ-1, gold then gets taken'
set test.uid = '11111111-0000-0000-0000-000000000002'; select mkt_accept_job('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001');
set test.uid = '11111111-0000-0000-0000-000000000001'; select mkt_accept_job('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001');
\echo '--- 9. silver now sees customer on its job'
set test.uid = '11111111-0000-0000-0000-000000000002'; select job_no, status, customer_name, mine from mkt_vendor_jobs('aaaaaaaa-0000-0000-0000-000000000002');
\echo '--- 10. gold cannot move silver job'
set test.uid = '11111111-0000-0000-0000-000000000001'; select mkt_advance_job('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','on_the_way');
set test.uid = '11111111-0000-0000-0000-000000000002';
\echo '--- 11. skipping a step refused'
select mkt_advance_job('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001','arrived');
select mkt_advance_job('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001','on_the_way');
select mkt_advance_job('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001','arrived');
select mkt_advance_job('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001','loading');
\echo '--- 12. in transit without 3 photos refused, with 3 ok'
select mkt_advance_job('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001','in_transit', null, array['a','b']);
select mkt_advance_job('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001','in_transit', null, array['a','b','c']);
\echo '--- 13. wrong OTP refused, right OTP delivers'
select mkt_advance_job('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001','delivered','0000');
select mkt_advance_job('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001','delivered','4321');
\echo '--- 14. wallet: 3000 + 1180 - 1200 (12% of 10000) = 2980'
select kind, amount from mkt_wallet_entries where org_id='aaaaaaaa-0000-0000-0000-000000000002' order by created_at;
select mkt_wallet_balance('aaaaaaaa-0000-0000-0000-000000000002') as balance;
\echo '--- 15. delivered again refused'
select mkt_advance_job('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001','delivered','4321');
\echo '--- 16. withdrawal below minimum refused, within allowed queued pending'
select mkt_request_wallet('aaaaaaaa-0000-0000-0000-000000000002','withdrawal',1500);
select mkt_request_wallet('aaaaaaaa-0000-0000-0000-000000000002','withdrawal',900);
select kind, amount, status from mkt_wallet_entries where org_id='aaaaaaaa-0000-0000-0000-000000000002' and status='pending';
select mkt_wallet_balance('aaaaaaaa-0000-0000-0000-000000000002') as balance_unchanged;
\echo '--- 17. vendor cannot read another org wallet balance'
select mkt_wallet_balance('aaaaaaaa-0000-0000-0000-000000000001') as other_org;
\echo '--- 18. vendor cannot write own score directly'
update mkt_vendors set score = 100 where org_id = 'aaaaaaaa-0000-0000-0000-000000000002';
reset role; select score from mkt_vendors where org_id='aaaaaaaa-0000-0000-0000-000000000002';
