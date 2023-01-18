# My first analyses using real-world data and techniques learned at Turing College.

___________________________________________________________________________________

## Marketing Analysis (2nd project)

### Task Description:
You have a follow up task from your marketing manager to identify overall trends of all marketing campaigns on your ecommerce site. She is particularly interested in finding out if users tend to spend more time on your website on certain weekdays and how that behavior differs across campaigns.

### Database Schema
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Marketing%20Analysis/Schema.JPG)


#### SQL Query for data extraction:

https://github.com/PauliusPigaga/First_Analyses/blob/main/Marketing%20Analysis/Marketing%20Analysis.sql#L1-L165


#### Presentation of analysis:
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Marketing%20Analysis/ABP.2_Marketing_Analysis%20(2)_page-0001.jpg)
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Marketing%20Analysis/ABP.2_Marketing_Analysis%20(2)_page-0002.jpg)
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Marketing%20Analysis/ABP.2_Marketing_Analysis%20(2)_page-0003.jpg)
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Marketing%20Analysis/ABP.2_Marketing_Analysis%20(2)_page-0004.jpg)
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Marketing%20Analysis/ABP.2_Marketing_Analysis%20(2)_page-0005.jpg)


## Product Analysis (1st project)

### Task Description:
You have a follow up task from your product manager to identify how much time it takes for a user to make a purchase on your website. Your PM would like to see the duration from first visit of a user on a particular day until first purchase on that same day. Your final result should show the duration dynamic daily.

## Database Schema
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Product%20Analysis/Schema.JPG)


## SQL Queries

Data without outliers:

```
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
```

Add Shipping Info To Purchase Funnel query:

```
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

```
Presentation of analysis:
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Product%20Analysis/ABP.1_Product_Analysis%20(2)_page-0001.jpg)
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Product%20Analysis/ABP.1_Product_Analysis%20(2)_page-0002.jpg)
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Product%20Analysis/ABP.1_Product_Analysis%20(2)_page-0003.jpg)
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Product%20Analysis/ABP.1_Product_Analysis%20(2)_page-0004.jpg)
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Product%20Analysis/ABP.1_Product_Analysis%20(2)_page-0005.jpg)
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Product%20Analysis/ABP.1_Product_Analysis%20(2)_page-0006.jpg)
![](https://github.com/PauliusPigaga/First_Analyses/blob/main/Product%20Analysis/ABP.1_Product_Analysis%20(2)_page-0007.jpg)

