# Hebrew Labels & RTL Conventions

## Dashboard RTL Support
Apply via card-mod:
```yaml
card_mod:
  style: |
    ha-card {
      direction: rtl;
    }
```

## Common Room Labels
| English | Hebrew |
|---------|--------|
| Living Room | סלון |
| Kitchen | מטבח |
| Bedroom / Parents | חדר שינה הורים |
| Lenny & Miley | חדר לני ומיילי |
| Ofri | חדר עפרי |
| Office | משרד |
| Hallway | מסדרון |
| Bathroom | חדר אמבטיה |
| Outdoor | חוץ |
| Warehouse | מחסן |
| Balcony | מרפסת |
| Service Room | חדר שירות |

## Common Entity Labels
| English | Hebrew |
|---------|--------|
| Light | אור |
| Fan | מאוורר |
| Cover / Shutter | תריס |
| Air Conditioner | מזגן |
| Lock | מנעול |
| Camera | מצלמה |
| Temperature | טמפרטורה |
| Humidity | לחות |
| Motion | תנועה |
| Door | דלת |
| Window | חלון |
| Boiler | דוד |
| Washing Machine | מכונת כביסה |
| Vacuum | שואב אבק |

## Status Labels
| English | Hebrew |
|---------|--------|
| On | פעיל |
| Off | כבוי |
| Open | פתוח |
| Closed | סגור |
| Home | בבית |
| Away | לא בבית |
| Occupied | תפוס |
| Available | זמין |
| Unavailable | לא זמין |

## Calendar Labels (from input_select.calendar_select)
- ימי הולדת (Birthdays)
- משפחה (Family)
- גוגל (Google)

## Calendar View Labels (from input_select.calendar_view)
- היום (Today)
- מחר (Tomorrow)
- שבוע (Week)
- שבועיים (Two Weeks)
- חודש (Month)
- חודשיים (Two Months)

## Time-Based Greetings (Universal Notifier)
| Time Slot | Hebrew |
|-----------|--------|
| Morning (06:00-12:00) | בוקר טוב |
| Afternoon (12:00-18:00) | צהריים טובים |
| Evening (18:00-22:00) | ערב טוב |
| Night (22:00-06:00) | לילה טוב |

## TTS Notes
- Hebrew language code: `he` (for service) / `iw` (for platform config)
- Use natural Hebrew word order
- Add dashes with time: "ב-7:30" not "ב7:30"
- Niqqud (vowel marks) not needed for basic TTS
- Optional `ha-nakdan` integration for improved pronunciation
