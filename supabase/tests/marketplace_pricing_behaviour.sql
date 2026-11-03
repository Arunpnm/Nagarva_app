-- Behaviour checks for 20261030_marketplace_pricing.sql on the local test
-- database (see marketplace_vendor_stubs.sql). Run after both migrations.
-- Sample rates below are TEST DATA for this script only, not a suggestion.
insert into mkt_rates values ('Chennai','standard',20,0.05,2999,now()),('Chennai','premium',26,0.06,2999,now()),('Chennai','economy',16,0.04,2999,now());
insert into mkt_city_prices (city,per_floor,car_local,car_base,car_per_km,bike_local,bike_base,bike_per_km,damage_cover,unpacking,storage_month) values ('Chennai',250,2500,3500,6,900,1500,2,1499,1800,2500);
update mkt_catalogue set services = jsonb_set(services,'{0,price}','400') where key='cot';
set role anon;
-- expect ok: move 2999 (min), floors 500, addons 1499, gst 899.64, total 5897.64, advance 999
select mkt_quote('{"from_city":"Chennai","to_city":"Chennai","package":"standard","lines":[{"key":"fridge","variant":1,"qty":1},{"key":"cot","variant":1,"qty":1,"services":["dis"]}],"pickup_floor":2,"pickup_lift":false,"drop_floor":4,"drop_lift":true,"addons":{"cover":true}}'::jsonb);
-- expect services 400 (dismantle charged on economy only)
select mkt_quote('{"from_city":"Chennai","to_city":"Chennai","package":"economy","lines":[{"key":"cot","variant":1,"qty":1,"services":["dis"]}]}'::jsonb)->>'services';
-- expect km 363, move 8390
select mkt_quote('{"from_city":"Chennai","to_city":"Bengaluru","package":"standard","lines":[{"key":"ward","variant":4,"qty":2},{"key":"sofa","variant":3,"qty":1}]}'::jsonb);
-- expect no_price (service tvu:dis), no_price (rates Bengaluru standard)
select mkt_quote('{"from_city":"Chennai","to_city":"Chennai","package":"economy","lines":[{"key":"tvu","variant":0,"qty":1,"services":["dis"]}]}'::jsonb);
select mkt_quote('{"from_city":"Bengaluru","to_city":"Bengaluru","package":"standard","lines":[{"key":"fridge","variant":0,"qty":1}]}'::jsonb);
-- expect unknown_item, city_not_served, bad_line
select mkt_quote('{"from_city":"Chennai","to_city":"Chennai","package":"standard","lines":[{"key":"nope","qty":1}]}'::jsonb)->>'reason', mkt_quote('{"from_city":"Mars","to_city":"Chennai","package":"standard","lines":[]}'::jsonb)->>'reason', mkt_quote('{"from_city":"Chennai","to_city":"Chennai","package":"standard","lines":[{"key":"fridge","qty":0}]}'::jsonb)->>'reason';
-- expect permission denied
insert into mkt_rates values ('Chennai','economy',1,0,1,now());
reset role;
