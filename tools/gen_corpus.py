#!/usr/bin/env python3
"""phase-02 — generates the parser golden corpus.

Models the Dart parser chain 1:1 (same regexes, same registry order)
so emitted expectations are exact. Regenerate:
    python3 tools/gen_corpus.py
Outputs:
    test/fixtures/corpus_notifications.json  (kind == notification)
    test/fixtures/corpus_sms.json            (kind == sms)
"""
import json, re
from pathlib import Path

RECEIVED = "2026-10-27T18:45:03+05:30"
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "test" / "fixtures"

# ---------------------------------------------------------------- model
DIGITS = {"०":"0","१":"1","२":"2","३":"3","४":"4","५":"5","६":"6","७":"7","८":"8","९":"9",
          "٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9"}
def norm_digits(t): return "".join(DIGITS.get(c, c) for c in t)

MARKED = re.compile(r'(?:₹|\brs\.?|\binr)\s*([0-9०-९][0-9०-९,]*(?:\.[0-9०-९]{1,2})?)', re.I)
BALCTX = re.compile(r'(bal|available|avail|a/c bal|account balance)', re.I)

def extract_paise(text):
    text = norm_digits(text)
    last_end = 0
    for m in MARKED.finditer(text):
        segment = text[last_end:m.start()]
        last_end = m.end()
        if BALCTX.search(segment):
            continue
        d = m.group(1).replace(",", "")
        if not d or d == ".":
            continue
        parts = d.split(".")
        whole = int(parts[0]) if parts[0] else 0
        paise = whole * 100
        if len(parts) == 2 and parts[1]:
            paise += int(parts[1].ljust(2, "0")[:2])
        return paise
    return None

NOISE_TAIL = {"private","pvt","ltd","limited","llp","india","pvt ltd","technologies",
    "technology","solutions","services","enterprises","traders","trading","retail",
    "stores","store","company","co","and","the","shop","outlet","branch"}

CHANNEL = re.compile(r'\s+(?:via|using|on|through)\s+(?:upi|gpay|google pay|phonepe|paytm|bhim|imps|neft)(?:\s+upi)?\s*$', re.I)

def squash(s): return re.sub(r'[^a-z0-9]', '', s.lower())

def strip_noise_tail(s):
    changed = True
    while changed:
        changed = False
        last = s.rsplit(' ', 1)[-1] if ' ' in s else s
        if squash(last) and squash(last) in NOISE_TAIL:
            s = s[:s.rfind(' ')].strip() if ' ' in s else ''
            changed = True
        t = re.sub(r'[\.,\-&]+$', '', s).strip()
        if t != s:
            s = t
            changed = True
        if not s:
            return s
    return s

def title_case(s):
    out = []
    for w in s.split(' '):
        if not w:
            out.append(w)
            continue
        all_upper = w == w.upper() and len(w) <= 3
        rest = w[1:]
        camel = any(c.isupper() for c in rest) and any(c.islower() for c in rest)
        out.append(w if (all_upper or camel) else w[0].upper() + w[1:].lower())
    return ' '.join(out)

def load_aliases():
    src = (ROOT / 'lib/data/parsers/merchant_cleaner.dart').read_text(encoding='utf-8')
    body = src.split('static const Map<String, String> aliases', 1)[1]
    body = body.split('};', 1)[0]
    pairs = re.findall(r"'([a-z0-9]+)':\s*(?:'([^']*)'|\"([^\"]*)\")", body)
    return {k: (a or b) for k, a, b in pairs}

ALIASES = load_aliases()

def clean(raw):
    if not raw.strip():
        return ''
    if '@' in raw:
        return raw.strip()
    s = re.sub(r'\s+', ' ', raw).strip()
    s = re.sub(r'\s*[\(\[][^\)\]]*[\)\]]', '', s)
    s = strip_noise_tail(s)
    a = ALIASES.get(squash(s))
    if a:
        return a
    s = re.sub(r'^[\W_]+|[\W_]+$', '', s)
    if not s:
        return raw.strip()
    return title_case(s)

def strip_channel(s): return CHANNEL.sub('', s).strip()

OTP_WORDS = re.compile(r'\b(otp|one[\s-]?time (password|code)|verification code|cvv|secure ?code)\b', re.I)
CODE_NUM = re.compile(r'\b\d{4,8}\b')
PROMO_WORDS = re.compile(r'\b(flat \d+ ?% ?off|\d+ ?% ?off|offer|offers|sale|coupon|discount|deal of the day|prize|lucky draw|congratulations! you (won|have won)|unsubscribe|click (here|now) to (win|claim)|cashback offer|reward points offer)\b', re.I)
MKT_SENDER = re.compile(r'^(jm|jd|lm|ad|vm)-?[a-z0-9]{2,10}', re.I)

def otp_filter(text):
    if OTP_WORDS.search(text) and CODE_NUM.search(text):
        return 'otp_security'
    return None

def promo_filter(text, sender):
    if PROMO_WORDS.search(text):
        return 'promo_marketing'
    if sender and MKT_SENDER.match(sender) and re.search('shop|sale|offer', text, re.I):
        return 'promo_marketing'
    return None

VPA_RE = re.compile(r'\b[\w.\-]{2,}@(?:ok[a-z]+|ybl|yapl|paytm|upi|ibl|axl)\b', re.I)

DV = re.compile(r'(?:sent|paid)\s*(?:₹|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:to|for)\s*([^\n]+)', re.I)
DA = re.compile(r'(?:₹|rs\.?|inr)\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:sent|paid)\s*(?:to|for)\s*([^\n]+)', re.I)
CV = re.compile(r'(?:received|got)\s*(?:₹|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:from)\s*([^\n]+)', re.I)
CA = re.compile(r'(?:₹|rs\.?|inr)\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:received|got)\s*(?:from)\s*([^\n]+)', re.I)
CV_PP = re.compile(r'(?:received|credited)\s*(?:₹|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:from)\s*([^\n]+)', re.I)
CA_PP = re.compile(r'(?:₹|rs\.?|inr)\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:received|credited)\s*(?:from)\s*([^\n]+)', re.I)

def upi_app_parse(text, app, conf_full, cv, ca):
    paise = extract_paise(text)
    if paise is None:
        return ('no_parser_match', None)
    debit = DV.search(text) or DA.search(text)
    credit = cv.search(text) or ca.search(text)
    m = debit or credit
    vpa = VPA_RE.search(text)
    if m:
        raw = strip_channel(m.group(2))
        return dict(amountPaise=paise, direction='debit' if debit else 'credit',
                    merchantClean=clean(raw), confidenceMin=conf_full,
                    parserId=app, hasVpa=bool(vpa))
    return dict(amountPaise=paise, direction='debit', merchantClean='Unknown',
                confidenceMin=0.7, parserId=app)

GENERIC_PROBE = re.compile(r'\bupi\b|\b@[a-z]{2,}\b.*paid|\bBHIM\b', re.I)
GDV = re.compile(r'(?:paid|sent|debited)\s*(?:₹|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:to|towards)\s*([^\n]+)', re.I)
GDA = re.compile(r'(?:₹|rs\.?|inr)\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:paid|sent|debited)\s*(?:to|towards)\s*([^\n]+)', re.I)
GCV = re.compile(r'(?:received|credited)\s*(?:₹|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:from)\s*([^\n]+)', re.I)
GCA = re.compile(r'(?:₹|rs\.?|inr)\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:received|credited)\s*(?:from)\s*([^\n]+)', re.I)

def generic_parse(text):
    if not GENERIC_PROBE.search(text):
        return ('no_parser_match', None)
    paise = extract_paise(text)
    if paise is None:
        return ('no_parser_match', None)
    debit = GDV.search(text) or GDA.search(text)
    credit = GCV.search(text) or GCA.search(text)
    m = debit or credit
    vpa = VPA_RE.search(text)
    if m:
        raw = strip_channel(m.group(2))
        return dict(amountPaise=paise, direction='debit' if debit else 'credit',
                    merchantClean=clean(raw), confidenceMin=0.65,
                    parserId='generic_upi', hasVpa=bool(vpa))
    return dict(amountPaise=paise, direction='debit',
                merchantClean=clean(vpa.group(0)) if vpa else 'Unknown',
                confidenceMin=0.65, parserId='generic_upi', hasVpa=bool(vpa))

DEBIT_WORD = re.compile(r'\b(debited|spent|paid)\b', re.I)
CREDIT_WORD = re.compile(r'\b(credited|received)\b', re.I)

BANKS = [
    dict(id='hdfc', tags=['HDFCBK','HDFC'], probe=re.compile('hdfc bank', re.I),
         ref=re.compile(r'\bREF\s*:?\s*(\d{6,})'),
         m=[re.compile(r'\bREF\s*:?\s*\d{6,}\s*([A-Za-z][\w .&/\-]*?)(?=\s*\.\s|\s*\.?\s*$|\s+Avl\b|\s+Available\b)'),
            re.compile(r'\bat\s+([A-Za-z][\w .&/\-]+?)\s+on\s')]),
    dict(id='sbi', tags=['SBI','SBIBNK','SBIIN'], probe=re.compile('state bank of india|sbi', re.I),
         ref=re.compile(r'(?:UPI\s*)?Ref(?:\.\s*|\s*No\.?|\s*:)?:?\s*(\d{6,})'),
         m=[re.compile(r'\bby\s+([A-Za-z][\w .&/\-]*?)(?=\s*\(|\s*\(?UPI|\s+Ref\b|\s*$)'),
            re.compile(r'\bfor\s+([A-Za-z][\w .&/\-]+?)(?=\s+on\s|\s*$)')]),
    dict(id='icici', tags=['ICICIB','ICICI'], probe=re.compile('icici bank', re.I),
         ref=re.compile(r'\bUPI[:/]\s*(\d{6,})'),
         m=[re.compile(r'\bInfo[:\s]+([A-Za-z][\w .&/\-]*?)(?=\s*\.\s|\s*\.?\s*$)'),
            re.compile(r'\bto\s+([A-Za-z][\w .&/\-]+?)\s*(?:\.|$)')]),
    dict(id='axis', tags=['AXISBK','AXISB','AXIS'], probe=re.compile('axis bank', re.I),
         ref=re.compile(r'Ref[:\s]*(\d{6,})'),
         m=[re.compile(r'\bRef[:\s]*\d{6,}\s+([A-Za-z][\w .&/\-]*?)(?=\s*\.\s|\s*\.?\s*$|\s+Avl\b|\s+Available\b)'),
            re.compile(r'\bto\s+([A-Za-z][\w .&/\-]+?)\s*(?:\.|$)')]),
    dict(id='kotak', tags=['KOTAKB','KOTAK'], probe=re.compile('kotak mahindra bank|kotak', re.I),
         ref=re.compile(r'Ref[:\s]*(\d{6,})'),
         m=[re.compile(r'\btowards\s+([A-Za-z][\w .&/\-]*?)(?=\s*\.\s|\s*\.?\s*$|\s+Ref\b|\s+Avl\b|\s+Available\b)'),
            re.compile(r'\bto\s+([A-Za-z][\w .&/\-]+?)\s*(?:\.|$)')]),
    dict(id='pnb', tags=['PNB','PNBIND'], probe=re.compile('punjab national bank|pnb', re.I),
         ref=re.compile(r'Ref[:\s]*(\d{6,})'),
         m=[re.compile(r'\bRef[:\s]*\d{6,}\s+([A-Za-z][\w .&/\-]*?)(?=\s*\.\s|\s*\.?\s*$|\s+Avl\b|\s+Available\b)'),
            re.compile(r'\bto\s+([A-Za-z][\w .&/\-]+?)\s*(?:\.|$)')]),
    dict(id='bob', tags=['BARDBKB','BANKOFBARODA','BOBIND'], probe=re.compile('bank of baroda|baroda', re.I),
         ref=re.compile(r'Ref[:\s]*(\d{6,})'),
         m=[re.compile(r'\)\s*([A-Za-z][\w .&/\-]*?)(?=\s*\.\s|\s*\.?\s*$|\s+Avl\b|\s+Available\b)'),
            re.compile(r'\bto\s+([A-Za-z][\w .&/\-]+?)\s*(?:\.|$)')]),
]

GPAY_PKG = 'com.google.android.apps.nbu.paysa'
PHONEPE_PKG = 'com.phonepe.app'
PAYTM_PKG = 'net.one97.paytm'
GPAY_PROBE = re.compile('google pay|gpay', re.I)
PHONEPE_PROBE = re.compile('phonepe', re.I)
PAYTM_PROBE = re.compile('paytm', re.I)

def bank_parse(b, text):
    is_debit = bool(DEBIT_WORD.search(text))
    is_credit = bool(CREDIT_WORD.search(text))
    if not (is_debit or is_credit):
        return ('no_parser_match', None)
    paise = extract_paise(text)
    if paise is None:
        return ('no_parser_match', None)
    ref = b['ref'].search(text)
    merchant = None
    for pat in b['m']:
        mm = pat.search(text)
        if mm and mm.group(1).strip():
            merchant = mm.group(1).strip()
            break
    full = merchant is not None
    d = dict(amountPaise=paise, direction='debit' if is_debit else 'credit',
             merchantClean=clean(merchant if merchant else 'Unknown'),
             confidenceMin=0.85 if full else 0.7, parserId=b['id'])
    if ref:
        d['hasRef'] = True
    return d

def run_chain(package, sender, text):
    r = otp_filter(text)
    if r:
        return ('drop', r)
    r = promo_filter(text, sender)
    if r:
        return ('drop', r)
    for b in BANKS:
        if (sender and any(t in sender.upper() for t in b['tags'])) or b['probe'].search(text):
            return bank_parse(b, text)
    if package == GPAY_PKG or GPAY_PROBE.search(text):
        return upi_app_parse(text, 'gpay', 0.95, CV, CA)
    if package == PHONEPE_PKG or PHONEPE_PROBE.search(text):
        return upi_app_parse(text, 'phonepe', 0.95, CV_PP, CA_PP)
    if package == PAYTM_PKG or PAYTM_PROBE.search(text):
        return upi_app_parse(text, 'paytm', 0.90, CV, CA)
    return generic_parse(text)

# ---------------------------------------------------------------- corpus
BANK_MERCHANTS = [
    ('SWIGGY', 'Swiggy'), ('ZOMATO', 'Zomato'), ('BLINKIT', 'Blinkit'),
    ('AMAZON PAY INDIA', 'Amazon Pay'), ('BIGBASKET', 'BigBasket'),
    ('DOMINOS PIZZA', "Domino's"), ('NETFLIX', 'Netflix'), ('TATA POWER', 'Tata Power'),
    ('BSES YAMUNA', 'BSES Yamuna'), ('AIRTEL', 'Airtel'), ('RAPIDO', 'Rapido'),
    ('IRCTC', 'IRCTC'), ('ZEPTO TECHNOLOGIES PVT LTD', 'Zepto'),
    ('FLIPKART INDIA PVT LTD', 'Flipkart'), ('AVENUE SUPERMARTS LTD', 'DMart'),
    ('RELIANCE FRESH', 'Reliance Fresh'), ('MCD', "McDonald's"), ('KFC', 'KFC'),
    ('NAMMA YATRI', 'Namma Yatri'), ('CHAI POINT', 'Chai Point'),
    ('SPOTIFY', 'Spotify'), ('VI', 'Vi'), ('CAFE COFFEE DAY', 'CCD'),
    ('STARBUCKS', 'Starbucks'),
]
APP_MERCHANTS = [('Swiggy', 'Swiggy'), ('zepto', 'Zepto'), ('BLINKIT', 'Blinkit')]
AMOUNTS_BANK = ['148', '148.50', '1,250', '2,500.75']
AMOUNTS_APP = ['148', '99.50', '1,250', '2,500.75', '72']
REFS = ['512345678901', '412345678901', '512345678', '4123456789012']

BANK_TEMPLATES = {
 'hdfc': [
  "Rs.{a} debited from A/c No. XX1234 on 27-10-26 REF {r} {m}.",
  "Rs.{a} credited to A/c No. XX1234 on 27-10-26 REF {r} {m}.",
  "Rs.{a} debited from A/c **1234 on 27-10-26 REF {r} {m}. Avl Bal Rs.12,345.67.",
  "Your A/c XX1234 debited Rs.{a} on 27-10-26 REF {r} {m}.",
  "Rs.{a} spent on A/c **1234 on 27-10-26 REF {r} {m}.",
 ],
 'sbi': [
  "Your A/c XX1234 debited on 27-10-26 for Rs.{a} by {m} (UPI Ref No {r}).",
  "Your A/c XX1234 credited on 27-10-26 for Rs.{a} by {m} (Ref No {r}).",
  "Your A/c XX1234 debited for Rs.{a} on 27-10-26 by {m} UPI Ref {r}.",
  "Rs.{a} debited from your A/c XX1234 on 27-10-26 by {m}. UPI Ref {r}. Avl Bal: Rs.8,000.",
  "Your A/c XX1234 is debited for Rs.{a} on 27-10-26 by {m} Ref {r}.",
 ],
 'icici': [
  "Your A/c XX1234 debited for Rs.{a} on 27-10-26. Info: {m}. UPI:{r}.",
  "Your A/c XX1234 credited for Rs.{a} on 27-10-26. Info: {m}. UPI: {r}.",
  "Rs.{a} debited from A/c XX1234 on 27-10-26. Info: {m}. UPI: {r}. Avl Bal Rs.5,000.",
  "Your A/c XX1234 debited Rs.{a} on 27-10-26. Info: {m}. UPI Ref {r}.",
  "ICICI Bank: Your A/c XX1234 credited Rs.{a} on 27-10-26. Info: {m}. UPI:{r}.",
 ],
 'axis': [
  "Rs.{a} debited from A/c 12345 on 27-10-26 UPI Ref {r} {m}.",
  "Rs.{a} credited to A/c 12345 on 27-10-26 Ref {r} {m}.",
  "Rs.{a} debited from A/c 12345 on 27-10-26 UPI Ref {r} {m}. Avl Bal Rs.3,456.78.",
  "Axis Bank: Rs.{a} debited from A/c 12345 on 27-10-26 UPI Ref {r} {m}.",
  "Axis Bank: Rs.{a} credited to A/c 12345 on 27-10-26 Ref {r} {m}.",
 ],
 'kotak': [
  "Rs.{a} debited from your CR A/c 123456 on 27-10-26 towards {m}. Ref {r}.",
  "Rs.{a} debited from A/c 123456 on 27-10-26 towards {m}. Ref {r}. Avl Bal: Rs.12,000.",
  "Rs.{a} credited to your CR A/c 123456 on 27-10-26 towards {m}. Ref {r}.",
  "Your CR A/c 123456 credited Rs.{a} on 27-10-26. Ref {r}.",
  "Kotak Mahindra Bank: Rs.{a} debited from A/c 123456 on 27-10-26 towards {m}. Ref {r}.",
 ],
 'pnb': [
  "Rs.{a} debited from your A/c 1234567890 on 27-10-26 UPI Ref {r} {m}.",
  "Rs.{a} credited to your A/c 1234567890 on 27-10-26 Ref {r} {m}.",
  "Your A/c 1234567890 debited Rs.{a} on 27-10-26 Ref {r} {m}.",
  "Rs.{a} debited from A/c 1234567890 on 27-10-26 UPI Ref {r} {m}. Avl Bal Rs.9,999.",
  "Punjab National Bank: Rs.{a} debited from A/c 1234567890 on 27-10-26 UPI Ref {r} {m}.",
 ],
 'bob': [
  "Rs.{a} debited from A/c 1234567890 on 27-10-26 (UPI Ref: {r}) {m}.",
  "Rs.{a} credited to A/c 1234567890 on 27-10-26 (Ref: {r}) {m}.",
  "Rs.{a} debited from A/c 1234567890 on 27-10-26 (UPI Ref: {r}) {m}. Avl Bal Rs.9,999.",
  "Bank of Baroda: Rs.{a} debited from A/c 1234567890 on 27-10-26 (UPI Ref: {r}) {m}.",
  "Rs.{a} credited to A/c 1234567890 on 27-10-26 (UPI Ref: {r}) {m}. Avl Bal Rs.21,000.",
 ],
}
BANK_SENDERS = {
 'hdfc': 'VM-HDFCBK', 'sbi': 'VM-SBI', 'icici': 'VM-ICICIB', 'axis': 'VM-AXISBK',
 'kotak': 'VM-KOTAKB', 'pnb': 'VM-PNBIND', 'bob': 'VM-BARDBKB',
}
APP_TEMPLATES = {
 'gpay': [
  "₹{a} sent to {m}",
  "You sent ₹{a} to {m}",
  "Paid ₹{a} to {m} via UPI",
  "Received ₹{a} from {m}",
  "₹{a} received from {m}",
 ],
 'phonepe': [
  "You paid ₹{a} to {m}",
  "₹{a} paid to {m} via PhonePe",
  "Sent ₹{a} to {m} on PhonePe",
  "₹{a} received from {m}",
  "You received ₹{a} from {m}",
 ],
 'paytm': [
  "₹{a} paid to {m}",
  "Paid ₹{a} to {m}",
  "₹{a} sent to {m} via Paytm UPI",
  "Received ₹{a} from {m}",
  "₹{a} received from {m}",
 ],
}
APP_PKG = {'gpay': GPAY_PKG, 'phonepe': PHONEPE_PKG, 'paytm': PAYTM_PKG}

def classify(d):
    return 'auto' if d.get('confidenceMin', 0) >= 0.8 else 'pending'

def build_sample(sid, kind, package, sender, text):
    res = run_chain(package, sender, text)
    if isinstance(res, tuple):
        if res[0] == 'no_parser_match':
            expect = {'class': 'drop', 'dropReason': 'no_parser_match'}
        else:
            expect = {'class': 'drop', 'dropReason': res[1]}
    else:
        expect = {'class': classify(res)}
        expect.update(res)
        expect['occurredAtIsoDate'] = '2026-10-27'
    return {'id': sid, 'kind': kind, 'packageKey': package, 'sender': sender,
            'text': text, 'expect': expect}

# ------------------------------------------------------------- adversarial
# (kind, package, sender, text, hand-expected fields)
ADV = [
 # drops: otp
 ('sms', None, 'VM-HDFCBK', 'Your OTP is 4832 for HDFC Bank netbanking login. Do not share with anyone.', {'class':'drop','dropReason':'otp_security'}),
 ('sms', None, 'VM-ICICIB', '123456 is your One Time Password (OTP). Valid for 5 minutes. -ICICI Bank', {'class':'drop','dropReason':'otp_security'}),
 ('sms', None, 'VM-HDFCBK', 'Use verification code 998877 to complete your ICICI Bank login.', {'class':'drop','dropReason':'otp_security'}),
 ('sms', None, None, 'Dear Customer, never share your CVV. Security code 4321 alert.', {'class':'drop','dropReason':'otp_security'}),
 ('sms', None, 'VM-SBI', 'OTP for Rs.5000 transaction: 778899. Do not share. SBI', {'class':'drop','dropReason':'otp_security'}),
 ('notification', GPAY_PKG, None, '556677 is your verification code for Google Pay', {'class':'drop','dropReason':'otp_security'}),
 # drops: promo
 ('sms', None, None, 'FLAT 50% OFF on all orders above Rs.500! Order now on Swiggy. Offer valid today only.', {'class':'drop','dropReason':'promo_marketing'}),
 ('sms', None, None, 'Congratulations! You have won a Rs.10000 prize. Click now to claim your reward.', {'class':'drop','dropReason':'promo_marketing'}),
 ('sms', None, None, 'Amazon Great Indian Sale - deal of the day: up to 80% discount!', {'class':'drop','dropReason':'promo_marketing'}),
 ('notification', PAYTM_PKG, None, 'Cashback offer! Get Rs.50 back on your next recharge.', {'class':'drop','dropReason':'promo_marketing'}),
 ('sms', None, None, 'Reply STOP to unsubscribe from these offers.', {'class':'drop','dropReason':'promo_marketing'}),
 # drops: no parser match
 ('sms', None, 'VM-HDFCBK', 'Dear Customer, your KYC is pending. Please visit your branch.', {'class':'drop','dropReason':'no_parser_match'}),
 ('sms', None, None, 'Mom called, call back when free', {'class':'drop','dropReason':'no_parser_match'}),
 ('sms', None, None, 'UPI transaction failed. Please retry after some time.', {'class':'drop','dropReason':'no_parser_match'}),
 ('sms', None, 'VM-ICICIB', 'Your A/c XX1234 will be credited with salary on 1st of next month.', {'class':'drop','dropReason':'no_parser_match'}),
 ('sms', None, 'VM-HDFCBK', 'Transaction of Rs.500 at SWIGGY using card ending 4321', {'class':'drop','dropReason':'no_parser_match'}),
 ('sms', None, 'VM-SBI', 'Your account balance is Rs.12,345.67 as on 27-10-26.', {'class':'drop','dropReason':'no_parser_match'}),
 ('sms', None, 'VM-AXISBK', 'EMI reminder: Rs.2,450 due on 05-11-26 from A/c 12345.', {'class':'drop','dropReason':'no_parser_match'}),
 # pending: partials
 ('notification', GPAY_PKG, None, 'Payment of ₹250 pending approval', {'class':'pending','parserId':'gpay','amountPaise':25000,'direction':'debit','merchantClean':'Unknown','confidenceMin':0.7}),
 ('sms', None, 'VM-ICICIB', 'Rs.350 debited from A/c XX1234 on 27-10-26.', {'class':'pending','parserId':'icici','amountPaise':35000,'direction':'debit','merchantClean':'Unknown','confidenceMin':0.7}),
 ('sms', None, 'VM-BARDBKB', 'Rs.350 debited from A/c 1234567890 on 27-10-26 (UPI Ref: 412345678901).', {'class':'pending','parserId':'bob','amountPaise':35000,'direction':'debit','merchantClean':'Unknown','confidenceMin':0.7}),
 ('sms', None, None, '₹१५० का भुगतान SWIGGY को भेजा गया via UPI', {'class':'pending','parserId':'generic_upi','amountPaise':15000,'direction':'debit','merchantClean':'Unknown','confidenceMin':0.65}),
 ('sms', None, None, 'Paid Rs.120 to RAMESH KIRANA via BHIM UPI', {'class':'pending','parserId':'generic_upi','amountPaise':12000,'direction':'debit','merchantClean':'Ramesh Kirana','confidenceMin':0.65}),
 ('sms', None, None, '₹500 received from PRIYA SHARMA via UPI', {'class':'pending','parserId':'generic_upi','amountPaise':50000,'direction':'credit','merchantClean':'Priya Sharma','confidenceMin':0.65}),
 ('notification', GPAY_PKG, None, 'Money sent to Swiggy: ₹150', {'class':'pending','parserId':'gpay','amountPaise':15000,'direction':'debit','merchantClean':'Unknown','confidenceMin':0.7}),
 ('notification', PAYTM_PKG, None, '₹1,000 deducted from wallet', {'class':'pending','parserId':'paytm','amountPaise':100000,'direction':'debit','merchantClean':'Unknown','confidenceMin':0.7}),
 ('notification', PHONEPE_PKG, None, 'Transaction ₹88 at CHAI POINT successful', {'class':'pending','parserId':'phonepe','amountPaise':8800,'direction':'debit','merchantClean':'Unknown','confidenceMin':0.7}),
 # auto: tricky-but-right
 ('sms', None, 'VM-HDFCBK', 'Avl Bal Rs.45,000. Rs.250 debited from A/c XX11 on 27-10-26 REF 512345678 SWIGGY.', {'class':'auto','parserId':'hdfc','amountPaise':25000,'direction':'debit','merchantClean':'Swiggy','confidenceMin':0.85}),
 ('sms', None, 'VM-HDFCBK', 'Rs.1,2,34,567.00 debited from A/c XX9988 on 27-10-26 REF 515151515151 LUXURY CARS PVT LTD.', {'class':'auto','parserId':'hdfc','amountPaise':123456700,'direction':'debit','merchantClean':'Luxury Cars','confidenceMin':0.85}),
 ('sms', None, 'VM-HDFCBK', 'Rs.15,000.00 credited to A/c XX5678 on 27-10-26 REF 512345678901 SALARY OCTOBER.', {'class':'auto','parserId':'hdfc','amountPaise':1500000,'direction':'credit','merchantClean':'Salary October','confidenceMin':0.85}),
 ('notification', GPAY_PKG, None, 'You sent ₹150 to ramesh@okhdfcbank', {'class':'auto','parserId':'gpay','amountPaise':15000,'direction':'debit','merchantClean':'ramesh@okhdfcbank','confidenceMin':0.95,'hasVpa':True}),
 ('notification', GPAY_PKG, None, 'Received ₹1,234.56 from AMAZON PAY INDIA', {'class':'auto','parserId':'gpay','amountPaise':123456,'direction':'credit','merchantClean':'Amazon Pay','confidenceMin':0.95}),
 ('notification', PHONEPE_PKG, None, 'You paid ₹1,499 to FLIPKART INDIA PVT LTD', {'class':'auto','parserId':'phonepe','amountPaise':149900,'direction':'debit','merchantClean':'Flipkart','confidenceMin':0.95}),
 ('notification', PAYTM_PKG, None, '₹99 paid to DOMINOS PIZZA', {'class':'auto','parserId':'paytm','amountPaise':9900,'direction':'debit','merchantClean':"Domino's",'confidenceMin':0.90}),
 ('sms', None, 'VM-SBI', 'Your A/c XX1234 debited on 27-10-26 for Rs.72.50 by UBER INDIA (UPI Ref No 412345678901).', {'class':'auto','parserId':'sbi','amountPaise':7250,'direction':'debit','merchantClean':'Uber','confidenceMin':0.85}),
 ('sms', None, 'VM-ICICIB', 'Your A/c XX1234 debited for Rs.399 on 27-10-26. Info: HOTSTAR. UPI:512345678901.', {'class':'auto','parserId':'icici','amountPaise':39900,'direction':'debit','merchantClean':'Hotstar','confidenceMin':0.85}),
 ('sms', None, 'VM-KOTAKB', 'Rs.55 debited from A/c 123456 on 27-10-26 towards CHAI POINT. Avl Bal Rs.4,321.00.', {'class':'auto','parserId':'kotak','amountPaise':5500,'direction':'debit','merchantClean':'Chai Point','confidenceMin':0.85}),
 ('sms', None, 'VM-PNBIND', 'Rs.2,500 debited from your A/c 1234567890 on 27-10-26 UPI Ref 412345678901 AVENUE SUPERMARTS LTD.', {'class':'auto','parserId':'pnb','amountPaise':250000,'direction':'debit','merchantClean':'DMart','confidenceMin':0.85}),
 ('sms', None, 'VM-BARDBKB', 'Rs.148.00 debited from A/c 1234567890 on 27-10-26 (UPI Ref: 412345678901) ZEPTO TECHNOLOGIES PVT LTD.', {'class':'auto','parserId':'bob','amountPaise':14800,'direction':'debit','merchantClean':'Zepto','confidenceMin':0.85}),
 ('sms', None, 'VM-AXISBK', 'Rs.75 debited from A/c 12345 on 27-10-26 UPI Ref 412345678901 NAMMA YATRI.', {'class':'auto','parserId':'axis','amountPaise':7500,'direction':'debit','merchantClean':'Namma Yatri','confidenceMin':0.85}),
 ('notification', GPAY_PKG, None, '₹0.50 sent to CHAI POINT', {'class':'auto','parserId':'gpay','amountPaise':50,'direction':'debit','merchantClean':'Chai Point','confidenceMin':0.95}),
 ('notification', GPAY_PKG, None, '₹1000000 sent to BUILDER via UPI', {'class':'auto','parserId':'gpay','amountPaise':100000000,'direction':'debit','merchantClean':'Builder','confidenceMin':0.95}),
 ('sms', None, 'VM-HDFCBK', 'Rs.249 spent on A/c **1234 on 27-10-26 REF 512345678 STARBUCKS.', {'class':'auto','parserId':'hdfc','amountPaise':24900,'direction':'debit','merchantClean':'Starbucks','confidenceMin':0.85}),
 ('sms', None, 'VM-PAYTMB', 'Rs.200 debited from Paytm Payments Bank A/c XX11 on 27-10-26 UPI:512345678901.', {'class':'pending','parserId':'paytm','amountPaise':20000,'direction':'debit','merchantClean':'Unknown','confidenceMin':0.7}),
 ('sms', None, 'VM-HDFCBK', 'Rs.99 debited from A/c XX11 on 27-10-26 REF 512345678 PAYTM FASTAG.', {'class':'auto','parserId':'hdfc','amountPaise':9900,'direction':'debit','merchantClean':'Paytm Fastag','confidenceMin':0.85}),
 ('sms', None, 'VM-KOTAKB', 'Rs.60 debited from your CR A/c 123456 on 27-10-26. Ref 512345678901.', {'class':'pending','parserId':'kotak','amountPaise':6000,'direction':'debit','merchantClean':'Unknown','confidenceMin':0.7}),
 ('sms', None, 'VM-ICICIB', 'Your A/c XX1234 credited for Rs.25,000.00 on 27-10-26. Info: GOOGLE INDIA PVT LTD. UPI:512345678901.', {'class':'auto','parserId':'icici','amountPaise':2500000,'direction':'credit','merchantClean':'Google','confidenceMin':0.85}),
 ('sms', None, 'VM-SBI', 'Your A/c XX1234 credited on 27-10-26 for Rs.1,100 by FLIPKART SERVICES (Ref No 412345678901).', {'class':'auto','parserId':'sbi','amountPaise':110000,'direction':'credit','merchantClean':'Flipkart','confidenceMin':0.85}),
 ('sms', None, None, 'Rs.45 paid to RAMESH GENERAL STORE via UPI', {'class':'pending','parserId':'generic_upi','amountPaise':4500,'direction':'debit','merchantClean':'Ramesh General','confidenceMin':0.65}),
 ('notification', GPAY_PKG, None, 'You sent ₹220.50 to MCD', {'class':'auto','parserId':'gpay','amountPaise':22050,'direction':'debit','merchantClean':"McDonald's",'confidenceMin':0.95}),
 ('sms', None, 'VM-HDFCBK', 'Rs.999.99 debited from A/c **1234 on 27-10-26 REF 512345678901 MYNTRA. Avl Bal Rs.1,000.00.', {'class':'auto','parserId':'hdfc','amountPaise':99999,'direction':'debit','merchantClean':'Myntra','confidenceMin':0.85}),
 ('sms', None, 'VM-AXISBK', 'Rs.4,000 credited to A/c 12345 on 27-10-26 Ref 412345678901 AMAZON PAY INDIA.', {'class':'auto','parserId':'axis','amountPaise':400000,'direction':'credit','merchantClean':'Amazon Pay','confidenceMin':0.85}),
 ('sms', None, 'VM-BARDBKB', 'Rs.30 debited from A/c 1234567890 on 27-10-26 (UPI Ref: 412345678901) BSES YAMUNA. Avl Bal Rs.9,999.', {'class':'auto','parserId':'bob','amountPaise':3000,'direction':'debit','merchantClean':'BSES Yamuna','confidenceMin':0.85}),
 ('notification', PHONEPE_PKG, None, 'Received ₹5,000 from N KIRANA ENTERPRISES', {'class':'auto','parserId':'phonepe','amountPaise':500000,'direction':'credit','merchantClean':'N Kirana','confidenceMin':0.95}),
 ('notification', GPAY_PKG, None, '₹148 paid to ZEPTO via UPI', {'class':'auto','parserId':'gpay','amountPaise':14800,'direction':'debit','merchantClean':'Zepto','confidenceMin':0.95}),
 ('sms', None, None, 'Rs.210 debited via UPI to vendor', {'class':'pending','parserId':'generic_upi','amountPaise':21000,'direction':'debit','merchantClean':'Unknown','confidenceMin':0.65}),
 ('sms', None, 'VM-HDFCBK', 'INR 350 debited from A/c XX1234 on 27-10-26 REF 512345678 AIRTEL.', {'class':'auto','parserId':'hdfc','amountPaise':35000,'direction':'debit','merchantClean':'Airtel','confidenceMin':0.85}),
 ('sms', None, 'VM-HDFCBK', 'Rs 45 debited from A/c XX1234 on 27-10-26 REF 512345678 SPOTIFY.', {'class':'auto','parserId':'hdfc','amountPaise':4500,'direction':'debit','merchantClean':'Spotify','confidenceMin':0.85}),
 ('notification', GPAY_PKG, None, '₹1,499.50 sent to BIGBASKET', {'class':'auto','parserId':'gpay','amountPaise':149950,'direction':'debit','merchantClean':'BigBasket','confidenceMin':0.95}),
 ('sms', None, 'VM-HDFCBK', 'Your A/c **1234 debited Rs.88 on 27-10-26 REF 512345678 CAFE COFFEE DAY.', {'class':'auto','parserId':'hdfc','amountPaise':8800,'direction':'debit','merchantClean':'CCD','confidenceMin':0.85}),
 ('notification', PAYTM_PKG, None, 'Sent ₹75 to freshmilk@paytm', {'class':'auto','parserId':'paytm','amountPaise':7500,'direction':'debit','merchantClean':'freshmilk@paytm','confidenceMin':0.90,'hasVpa':True}),
 ('notification', PHONEPE_PKG, None, 'You paid ₹60 to bhuttawala@ybl', {'class':'auto','parserId':'phonepe','amountPaise':6000,'direction':'debit','merchantClean':'bhuttawala@ybl','confidenceMin':0.95,'hasVpa':True}),
 ('notification', None, None, 'Sent ₹500 to SWIGGY via Google Pay', {'class':'auto','parserId':'gpay','amountPaise':50000,'direction':'debit','merchantClean':'Swiggy','confidenceMin':0.95}),
 ('notification', None, None, '₹25 paid to CHAI WALA using PhonePe', {'class':'auto','parserId':'phonepe','amountPaise':2500,'direction':'debit','merchantClean':'Chai Wala','confidenceMin':0.95}),
 ('sms', None, 'VM-PNBIND', 'Rs.900 credited to your A/c 1234567890 on 27-10-26 Ref 412345678901 VI RECHARGE.', {'class':'auto','parserId':'pnb','amountPaise':90000,'direction':'credit','merchantClean':'VI Recharge','confidenceMin':0.85}),
]

def main():
    assert len(ALIASES) >= 60, f'alias table too small: {len(ALIASES)}'
    samples = []
    sid = [0]
    def nxt(p):
        sid[0] += 1
        return f'{p}_{sid[0]:04d}'

    for bank, tpls in BANK_TEMPLATES.items():
        for ti, tpl in enumerate(tpls):
            for mi in range(4):
                m, _mc = BANK_MERCHANTS[(ti * 4 + mi) % len(BANK_MERCHANTS)]
                a = AMOUNTS_BANK[(ti + mi) % len(AMOUNTS_BANK)]
                r = REFS[(ti + mi) % len(REFS)]
                samples.append(build_sample(nxt(bank), 'sms', None, BANK_SENDERS[bank], tpl.format(a=a, m=m, r=r)))
    for app, tpls in APP_TEMPLATES.items():
        for ti, tpl in enumerate(tpls):
            for mi in range(3):
                m, _mc = APP_MERCHANTS[mi % len(APP_MERCHANTS)]
                a = AMOUNTS_APP[(ti + mi) % len(AMOUNTS_APP)]
                samples.append(build_sample(nxt(app), 'notification', APP_PKG[app], None, tpl.format(a=a, m=m)))
    n_templates = len(samples)

    # adversarial: verify model vs hand expectations
    mismatches = []
    for kind, pkg, sender, text, hand in ADV:
        s = build_sample('adv', kind, pkg, sender, text)
        for k, v in hand.items():
            got = s['expect'].get(k)
            if got != v:
                mismatches.append((text[:60], k, v, got))
        s['id'] = nxt('adv')
        samples.append(s)
    if mismatches:
        print('!! MODEL vs HAND-EXPECTATION MISMATCHES:')
        for t, k, want, got in mismatches:
            print(f'  {t!r}\n    {k}: want={want!r} got={got!r}')
        raise SystemExit(1)

    notifications = [s for s in samples if s['kind'] == 'notification']
    sms = [s for s in samples if s['kind'] == 'sms']
    from collections import Counter
    cls = Counter(s['expect']['class'] for s in samples)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, data in (('corpus_notifications.json', notifications), ('corpus_sms.json', sms)):
        payload = {'receivedAtIso': RECEIVED, 'samples': data}
        OUT.joinpath(name).write_text(json.dumps(payload, indent=1, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f'templates={n_templates} adversarial={len(ADV)} total={len(samples)} '
          f'(notif={len(notifications)}, sms={len(sms)}) classes={dict(cls)}')
    assert len(samples) == 250, len(samples)

if __name__ == '__main__':
    main()
