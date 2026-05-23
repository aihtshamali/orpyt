# App Store Pricing Setup

Last checked: May 23, 2026

## Current App Store Connect Setup

### App Price
- Base country or region: United Kingdom
- App price: Free
- Availability: 175 countries or regions
- Tax category: App Store software
- Export checked: `/Users/aihtsham/Downloads/Current Price.csv`
- CSV result: 175 regions, all app download prices are `0`

### Subscription Group
- Group reference name: `Orpyt Pro`
- Subscription count: 2
- Streamlined purchasing: On
- Billing grace period: should be enabled before production submission

## Products

### Orpyt Pro Monthly
- Product ID: `com.orpyt.pro.monthly`
- Apple ID: `6765900803`
- Status: Approved
- Duration: 1 month
- United States price: `$0.99/month`
- Introductory offer: free for the first week
- Availability: all 175 countries or regions
- Export checked: `/Users/aihtsham/Downloads/Starting Subscription Price.csv`
- CSV result: 175 regions, all subscription prices are non-zero

Approved English (U.K.) localization:
- Display name: `Orpyt Pro Monthly`
- Description: `Flexible access to Orpyt Pro with all features`

### Orpyt Pro Yearly
- Product ID: `com.orpyt.pro.yearly`
- Apple ID: `6765900917`
- Status: Approved
- Duration: 1 year
- United States upfront price: `$9.99/year`
- Introductory offer: free for the first week
- Availability: all 175 countries or regions

Approved English (U.K.) localization:
- Display name: `Orpyt Pro Yearly`
- Description: `Best value for time-zone work with weather, calendar`

Recommended final English description:
`Best value for time-zone work with weather, calendar context, meeting alerts, and planning tools.`

## Recommendation

Keep this model for launch:
- Free app download
- Pro Monthly: `$0.99/month`
- Pro Yearly: `$9.99/year`
- 7-day free trial on both
- Yearly shown as the recommended option in-app

Avoid enabling `Monthly with 12-Month Commitment` on the yearly product while the standalone monthly product exists. If App Store Connect requires it for regional pricing, keep the yearly upfront option primary and use `$0.99/month` for the commitment price.

The clean user-facing choice should be:
- Pay monthly for flexibility
- Pay yearly for the best value

## Future Pricing Path

After the app has more reviews and stronger screenshots, consider:
- Monthly: `$1.99/month`
- Yearly: `$14.99/year`
- Optional lifetime purchase: `$29.99-$39.99`, if a non-consumable product is added

Do not raise pricing until the App Store page has enough trust signals: polished screenshots, clear privacy policy URL, review prompt flow, and early ratings.
