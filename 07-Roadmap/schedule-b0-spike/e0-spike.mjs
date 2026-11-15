// E0 spike (Eat Now manual capture gate). Razorpay TEST mode only. Node 20.6+.
//   node e0-spike.mjs range            no payment: which manual_expiry_period values the order API accepts
//   node e0-spike.mjs dup              pay an automatic-capture order, then try to pay it again (C4: expect no 2nd capture / auto-refund)
//   node e0-spike.mjs route            Route + manual capture: authorise, capture, transfer, refund with reversal (C9)
// Keys: RZP_KEY_ID (rzp_test_...) + RZP_KEY_SECRET; `route` also needs RZP_LINKED_ACCOUNT (acc_...), a TEST linked account.
// Reuse the backend env file without printing it:  node --env-file=<path> e0-spike.mjs <mode>
import http from 'node:http';

const KEY_ID = process.env.RZP_KEY_ID ?? process.env.RAZORPAY_KEY_ID ?? '';
const KEY_SECRET = process.env.RZP_KEY_SECRET ?? process.env.RAZORPAY_KEY_SECRET ?? '';
const LINKED = process.env.RZP_LINKED_ACCOUNT ?? '';
const mode = process.argv[2];
if (!KEY_ID.startsWith('rzp_test_') || !KEY_SECRET || !['range', 'dup', 'route'].includes(mode)) {
  console.error('Set RZP_KEY_ID (rzp_test_...) and RZP_KEY_SECRET, then: node e0-spike.mjs range|dup|route');
  process.exit(1);
}
if (mode === 'route' && !LINKED.startsWith('acc_')) {
  console.error('route mode needs RZP_LINKED_ACCOUNT=acc_... (a test-mode linked account)');
  process.exit(1);
}

const AUTH = 'Basic ' + Buffer.from(`${KEY_ID}:${KEY_SECRET}`).toString('base64');
const results = [];
const check = (name, pass, detail = '') => {
  results.push(pass);
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? '  -> ' + detail : ''}`);
};
const info = (name, detail) => console.log(`INFO  ${name}  -> ${detail}`);
const sleep = ms => new Promise(r => setTimeout(r, ms));

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
const err = r => r.json?.error?.description ?? JSON.stringify(r.json);

function serveCheckout(orderId, title) {
  const page = `<!doctype html><meta charset="utf-8"><title>E0 checkout</title>
<body style="font-family:system-ui;max-width:520px;margin:40px auto">
<h3>E0 spike - ${title}</h3><p>Order ${orderId}. Choose UPI, enter success@razorpay. Reload the page to try again.</p>
<button id="b">Open checkout</button><pre id="o"></pre>
<script src="https://checkout.razorpay.com/v1/checkout.js"></script>
<script>
const r = new Razorpay({ key: ${JSON.stringify(KEY_ID)}, order_id: ${JSON.stringify(orderId)}, amount: 100, currency: 'INR', name: 'E0 spike',
  handler: x => document.getElementById('o').textContent = 'callback: ' + JSON.stringify(x) });
r.on('payment.failed', x => document.getElementById('o').textContent = 'failed: ' + JSON.stringify(x.error));
document.getElementById('b').onclick = () => r.open();
</script></body>`;
  const server = http.createServer((_, res) => { res.setHeader('Content-Type', 'text/html'); res.end(page); });
  return new Promise(resolve => server.listen(4173, '127.0.0.1', () => resolve(server)));
}

async function waitFor(orderId, pred, seconds) {
  for (let i = 0; i < seconds / 3; i++) {
    const { json } = await rz('GET', `/orders/${orderId}/payments`);
    const hit = (json?.items ?? []).find(pred);
    if (hit) return hit;
    await sleep(3000);
  }
  return null;
}

if (mode === 'range') {
  // Which manual_expiry_period values does the order API accept (docs: >= automatic 12 min, <= 7200)?
  for (const m of [1, 11, 12, 60, 120, 7200, 7201]) {
    const r = await rz('POST', '/orders', {
      amount: 100, currency: 'INR', receipt: `e0-range-${m}-${Date.now()}`,
      payment: { capture: 'manual', capture_options: { manual_expiry_period: m, refund_speed: 'normal' } },
    });
    info(`manual_expiry_period=${m}`, r.status === 200 ? 'accepted' : `${r.status} ${err(r)}`);
  }
  const ok = await rz('POST', '/orders', {
    amount: 100, currency: 'INR', receipt: `e0-range-120-${Date.now()}`,
    payment: { capture: 'manual', capture_options: { manual_expiry_period: 120, refund_speed: 'normal' } },
  });
  check('120 min (the planned Eat Now value) accepted', ok.status === 200);
}

if (mode === 'dup') {
  // Automatic capture follows the Dashboard setting (B0: Automatic). Pay once, then try to pay the same order again.
  const o = await rz('POST', '/orders', { amount: 100, currency: 'INR', receipt: `e0-dup-${Date.now()}` });
  check('order created (account default capture)', o.status === 200, o.status === 200 ? o.json.id : err(o));
  if (o.status !== 200) process.exit(1);
  const server = await serveCheckout(o.json.id, 'pay ONCE, then reload and pay AGAIN');
  console.log('\nOpen http://127.0.0.1:4173 , pay with UPI success@razorpay. Waiting up to 5 min for the first payment...\n');
  const p1 = await waitFor(o.json.id, x => x.status === 'captured' || x.status === 'authorized', 300);
  if (!p1) { server.close(); console.log('No first payment; rerun.'); process.exit(1); }
  info('first payment', `${p1.id} status=${p1.status}`);
  console.log('\nNow reload the page and pay the SAME order again (success@razorpay). Waiting up to 5 min...\n');
  await waitFor(o.json.id, x => x.id !== p1.id, 300);
  server.close();
  await sleep(5000);
  const all = (await rz('GET', `/orders/${o.json.id}/payments`)).json?.items ?? [];
  const ord = (await rz('GET', `/orders/${o.json.id}`)).json;
  for (const x of all) info('payment on order', `${x.id} status=${x.status} refunded=${x.amount_refunded ?? 0} err=${x.error_code ?? ''} ${x.error_description ?? ''}`);
  info('order', `status=${ord?.status} amount_paid=${ord?.amount_paid}`);
  const captured = all.filter(x => x.status === 'captured' || (x.amount_refunded ?? 0) > 0 && x.captured);
  check('C4: money for the order is taken once (<= 1 captured payment, extras refunded or blocked)',
    all.filter(x => x.status === 'captured').length <= 1 && (ord?.amount_paid ?? 0) <= 100,
    `captured=${captured.length} of ${all.length}`);
}

if (mode === 'route') {
  const o = await rz('POST', '/orders', {
    amount: 100, currency: 'INR', receipt: `e0-route-${Date.now()}`,
    payment: { capture: 'manual', capture_options: { manual_expiry_period: 120, refund_speed: 'normal' } },
    transfers: [{ account: LINKED, amount: 100, currency: 'INR', on_hold: 0 }],
  });
  check('C9a order accepts manual capture + transfers together', o.status === 200, o.status === 200 ? o.json.id : err(o));
  if (o.status !== 200) process.exit(1);
  const server = await serveCheckout(o.json.id, 'Route + manual capture: pay with success@razorpay');
  console.log('\nOpen http://127.0.0.1:4173 , pay with UPI success@razorpay. Waiting up to 5 min...\n');
  const p = await waitFor(o.json.id, x => x.status === 'authorized' || x.status === 'captured', 300);
  server.close();
  if (!p) { console.log('No payment; rerun.'); process.exit(1); }
  check('C9b payment stays authorized under manual capture', p.status === 'authorized', `status=${p.status}`);
  const t0 = await rz('GET', `/payments/${p.id}/transfers`);
  info('transfers before capture', `${t0.status} count=${t0.json?.items?.length ?? 'n/a'} ${t0.json?.items?.map(t => t.status).join(',') ?? err(t0)}`);
  const cap = await rz('POST', `/payments/${p.id}/capture`, { amount: 100, currency: 'INR' });
  check('C9c capture accepted', cap.status === 200 && cap.json?.status === 'captured', `${cap.status} ${cap.json?.status ?? err(cap)}`);
  await sleep(8000);
  const t1 = await rz('GET', `/payments/${p.id}/transfers`);
  const tr = t1.json?.items?.[0];
  check('C9d transfer exists after capture', !!tr, tr ? `${tr.id} status=${tr.status} amount=${tr.amount} recipient=${tr.recipient}` : err(t1));
  const rf = await rz('POST', `/payments/${p.id}/refund`, { amount: 100, reverse_all: 1 });
  check('C9e refund with reverse_all accepted', rf.status === 200, `${rf.status} ${rf.json?.id ?? err(rf)}`);
  await sleep(8000);
  const t2 = await rz('GET', `/payments/${p.id}/transfers`);
  const tr2 = t2.json?.items?.[0];
  check('C9f transfer reversed after refund', !!tr2 && (tr2.amount_reversed ?? 0) >= 100, tr2 ? `amount_reversed=${tr2.amount_reversed} status=${tr2.status}` : err(t2));
}

console.log(`\n${results.filter(Boolean).length}/${results.length} checks passed`);
