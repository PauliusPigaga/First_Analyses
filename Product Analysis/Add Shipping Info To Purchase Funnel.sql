WITH CleanData AS -- I took columns that I thought I would need and changed the formats
(
  SELECT
    PARSE_DATE('%Y%m%d',event_date) event_date,
    TIMESTAMP_MICROS(event_timestamp) event_timestamp,
    event_name,
    user_pseudo_id,
    event_value_in_usd,
    category,
    operating_system,
    browser,
    browser_version,
    country
  FROM `tc-da-1.turing_data_analytics.raw_events`
)
, AddShippingInfo AS -- Calculating # of Users in Add_Shipping_Info Event and Average Time to complete this step
(
  SELECT
    event_date,
    user_pseudo_id,
    MIN(event_timestamp) add_shipping_timestamp
  FROM CleanData
  WHERE event_name = 'add_shipping_info'
  GROUP BY event_date,user_pseudo_id
  ORDER BY event_date
)
, AddPaymentInfo AS -- Calculating # of Users in Add_Payment_Info Event and Average Time to complete this step
(
  SELECT
    event_date,
    user_pseudo_id,
    MIN(event_timestamp) add_payment_timestamp
  FROM CleanData
  WHERE event_name = 'add_payment_info'
  GROUP BY event_date,user_pseudo_id
  ORDER BY event_date
)
, Purchase AS -- Calculating # of Users who purchased.
(
  SELECT
    event_date,
    user_pseudo_id,
    MIN(event_timestamp) purchase_timestamp
  FROM CleanData
  WHERE event_name = 'purchase'
  GROUP BY event_date,user_pseudo_id
  ORDER BY event_date
)
,FullTable AS -- Joining All Information Together
(SELECT
  AddShippingInfo.event_date,
  AddShippingInfo.user_pseudo_id,
  AddShippingInfo.add_shipping_timestamp,
  AddPaymentInfo.add_payment_timestamp,
  Purchase.purchase_timestamp
FROM AddShippingInfo
LEFT JOIN AddPaymentInfo ON
  AddShippingInfo.event_date = AddPaymentInfo.event_date
  AND
  AddShippingInfo.user_pseudo_id = AddPaymentInfo.user_pseudo_id
LEFT JOIN Purchase ON
  AddShippingInfo.event_date = Purchase.event_date
  AND
  AddShippingInfo.user_pseudo_id = Purchase.user_pseudo_id
)
SELECT -- Aggregating the data.
  COUNT(add_shipping_timestamp) Shipping_Users_Count,
  ROUND(AVG(timestamp_diff(add_payment_timestamp,add_shipping_timestamp, MINUTE)) , 2)Shipping_and_payment_difference,
  COUNT(add_payment_timestamp) Payment_Users_Count,
  ROUND(AVG(timestamp_diff(purchase_timestamp,add_payment_timestamp, MINUTE)) , 2 )Payment_and_Purchase_difference,
  COUNT(purchase_timestamp) Purchase_Users_Count
FROM FullTable