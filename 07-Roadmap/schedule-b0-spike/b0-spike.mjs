// B0 spike, no Postman. Usage:  node b0-spike.mjs ok     |   node b0-spike.mjs fail
// Keys come from the environment (RZP_KEY_ID / RZP_KEY_SECRET, or the backend's RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET);
// test keys only. To reuse the backend's env file without printing it:  node --env-file=<path> b0-spike.mjs ok
// Needs Node 20.6+.
import http from 'node:http';

const KEY_ID = process.env.RZP_KEY_ID ?? process.env.RAZORPAY_KEY_ID ?? '';
const KEY_SECRET = process.env.RZP_KEY_SECRET ?? process.env.RAZORPAY_KEY_SECRET ?? '';
const mode = process.argv[2];
if (!KEY_ID.startsWith('rzp_test_') || !KEY_SECRET || !['ok', 'fail'].includes(mode)) {
  console.error('Set RZP_KEY_ID (rzp_test_...) and RZP_KEY_SECRET, then: node b0-spike.mjs ok|fail');
  process.exit(1);
}

const AUTH = 'Basic ' + Buffer.from(`${KEY_ID}:${KEY_SECRET}`).toString('base64');
const results = [];
const check = (name, pass, detail = '') => {
  results.push(pass);
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? '  -> ' + detail : ''}`);
};

async function rz(method, path, body) {
  const res = await fetch('https://api.razorpay.com/v1' + path, {
    method,
    headers: { Authorization: AUTH, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch { /* non-json body */ }
  return { status: res.status, json };
}

const manualOrder = (receipt, withOptions) => ({
  amount: 100,
  currency: 'INR',
  receipt,
  payment: withOptions
    ? { capture: 'manual', capture_options: { manual_expiry_period: 120, refund_speed: 'normal' } }
    : { capture: 'manual' },
});

function serveCheckout(orderId) {
  const page = `<!doctype html><meta charset="utf-8"><title>B0 checkout</title>
<body style="font-family:system-ui;max-width:520px;margin:40px auto">
<h3>B0 spike - ${mode === 'ok' ? 'pay with UPI success@razorpay' : 'pay with UPI failure@razorpay'}</h3>
<p>Order ${orderId}. Choose UPI, enter the VPA above.</p><button id="b">Open checkout</button><pre id="o"></pre>
<script src="https://checkout.razorpay.com/v1/checkout.js"></script>
<script>
const r = new Razorpay({ key: ${JSON.stringify(KEY_ID)}, order_id: ${JSON.stringify(orderId)}, amount: 100, currency: 'INR', name: 'B0 spike',
  handler: x => document.getElementById('o').textContent = 'callback: ' + JSON.stringify(x) });
r.on('payment.failed', x => document.getElementById('o').textContent = 'failed: ' + JSON.stringify(x.error));
document.getElementById('b').onclick = () => r.open();
</script></body>`;
  const server = http.createServer((_, res) => { res.setHeader('Content-Type', 'text/html'); res.end(page); });
  return new Promise(resolve => server.listen(4173, '127.0.0.1', () => resolve(server)));
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function waitForPayment(orderId) {
  for (let i = 0; i < 100; i++) { // ~5 min
    const { json } = await rz('GET', `/orders/${orderId}/payments`);
    const items = json?.items ?? [];
    const p = mode === 'ok'
      ? items.find(x => x.status === 'authorized' || x.status === 'captured') // ignore earlier failed attempts
      : items.find(x => x.status === 'failed');
    if (p) return p;
    await sleep(3000);
  }
  return null;
}

// P1: capture_options accepted with manual; P1b: manual without capture_options (informational)
const a = await rz('POST', '/orders', manualOrder(`b0-${mode}-${Date.now()}`, true));
check('P1  order accepted with capture:manual + capture_options', a.status === 200, a.status === 200 ? a.json.id : JSON.stringify(a.json));
if (a.status !== 200) process.exit(1);
if (mode === 'ok') {
  const b = await rz('POST', '/orders', manualOrder(`b0-nocapopt-${Date.now()}`, false));
  check('P1b manual without capture_options accepted (informational)', b.status === 200, b.status === 200 ? '' : JSON.stringify(b.json));
}

const orderId = a.json.id;
let server = null;
if (process.argv[3] === '--api') {
  // headless: server-to-server payment creation (needs the account feature; test mode only)
  const vpa = mode === 'ok' ? 'success@razorpay' : 'failure@razorpay';
  const pay = await rz('POST', '/payments/create/json', {
    amount: 100, currency: 'INR', order_id: orderId, email: 'b0@example.com', contact: '9999999999', method: 'upi', vpa,
  });
  console.log(`direct payment create (${vpa}): HTTP ${pay.status} ${pay.json?.error?.description ?? pay.json?.razorpay_payment_id ?? ''}`);
  if (pay.status >= 400) process.exit(1);
} else {
  server = await serveCheckout(orderId);
  console.log(`\nOpen http://127.0.0.1:4173 in a browser and pay with UPI ${mode === 'ok' ? 'success@razorpay' : 'failure@razorpay'}.\nWaiting up to 5 min for the payment to appear...\n`);
}

const p = await waitForPayment(orderId);
server?.close();
if (!p) { console.log('No payment appeared in 5 min; rerun.'); process.exit(1); }
console.log(`payment ${p.id}: status=${p.status} method=${p.method}`);

if (mode === 'ok') {
  check('P3  manual order overrides dashboard auto-capture: status authorized', p.status === 'authorized', `status=${p.status}`);
  check('P4  method is upi', p.method === 'upi', `method=${p.method}`);
  const c1 = await rz('POST', `/payments/${p.id}/capture`, { amount: 100, currency: 'INR' });
  check('P5  capture accepted -> captured', c1.status === 200 && c1.json?.status === 'captured', `${c1.status} ${c1.json?.status ?? JSON.stringify(c1.json)}`);
  const c2 = await rz('POST', `/payments/${p.id}/capture`, { amount: 100, currency: 'INR' });
  const d = (c2.json?.error?.description ?? '').toLowerCase();
  check('P6  second capture -> 400 already captured', c2.status === 400 && d.includes('already been captured'), `${c2.status} ${c2.json?.error?.description ?? ''}`);
} else {
  check('P7  failed UPI payment has status failed', p.status === 'failed', `status=${p.status} ${p.error_code ?? ''} ${p.error_description ?? ''}`);
  const c = await rz('POST', `/payments/${p.id}/capture`, { amount: 100, currency: 'INR' });
  check('P8  failed payment cannot be captured (4xx)', c.status >= 400 && c.status < 500, `${c.status} ${c.json?.error?.description ?? ''}`);
}

console.log(`\n${results.filter(Boolean).length}/${results.length} passed`);
