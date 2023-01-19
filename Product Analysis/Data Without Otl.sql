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
, FirstVisit AS -- Calculating the first visit timestamp in a day by a user
(
  SELECT
    event_date,
    user_pseudo_id,
    MIN(event_timestamp) visit_timestamp
  FROM CleanData
  GROUP BY event_date,user_pseudo_id
)
, PurchasePrep AS -- Calculating the first purchase timestamp in a day by a user
(
  SELECT
    event_date,
    user_pseudo_id,
    MIN(event_timestamp) purchase_timestamp
  FROM CleanData
  WHERE event_name = 'purchase'
  GROUP BY event_date,user_pseudo_id
)
, Purchase AS -- Joining other columns to purchase timestamp information.
(
  SELECT 
    a.*,
    b.event_value_in_usd,
    b.category,
    b.operating_system,
    b.browser,
    b.browser_version,
    b.country
  FROM PurchasePrep a
  JOIN CleanData b ON
  a.user_pseudo_id = b.user_pseudo_id AND a.purchase_timestamp =  b.event_timestamp
)
,TimeDifference AS -- Time difference between first visit and purchase
(
  SELECT
  FirstVisit.event_date,
  FirstVisit.user_pseudo_id,
  FirstVisit.visit_timestamp,
  Purchase.purchase_timestamp,
  Purchase.event_value_in_usd,
  Purchase.category,
  Purchase.operating_system,
  Purchase.browser,
  Purchase.browser_version,
  Purchase.country,
  TIMESTAMP_DIFF(purchase_timestamp, visit_timestamp, MINUTE) Time_Difference
FROM FirstVisit
JOIN Purchase 
  ON FirstVisit.user_pseudo_id = Purchase.user_pseudo_id 
  AND firstvisit.event_date = Purchase.event_date
ORDER BY FirstVisit.event_date
)
,AvgStddev AS -- Calculating average and Standard Deviation.This will be used for removing outliers
(
SELECT
  AVG(TimeDifference.Time_Difference) Average,
  STDDEV(TimeDifference.Time_Difference) Standard_deviation
FROM TimeDifference
)
SELECT 
  * 
FROM TimeDifference,AvgStddev 
WHERE event_value_in_usd > 0 -- There is some purchases without any value
  AND Time_Difference < (Average + 2 * Standard_deviation) -- Decided to remove outliers using Standard Deviation.Purchases that took more than 422Minutes to do,will not be showed in Daily Purchase Duration Chart.