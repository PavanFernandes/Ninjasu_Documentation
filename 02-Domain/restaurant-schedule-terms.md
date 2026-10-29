---
id: ""
title: "Restaurant terms for Schedule (rules to put in the onboarding contract)"
summary: "Business rules that bind the restaurant on Schedule orders (who bears an unsupplied item, payout deductions, cancel freeze, commission notice). Not legal text: a list of decided rules for the contract to carry."
type: domain
status: draft
apps: [backend, web]
module: "schedule"
anchors: []
verified_against: ""
updated: 2026-10-29
---

# Restaurant terms for Schedule

Rules Samivan has decided that bind the restaurant. Each must appear in the restaurant onboarding contract before the HSR pilot, and the restaurant must see them when it is onboarded. This page is a list of decisions, not contract wording: legal text and the GST treatment need review by a lawyer and a CA.

When a decision makes the restaurant bear a cost or loses a right, add a row here in the same change as the decision.

| # | rule the restaurant is bound by | decided by, date | where decided |
|---|---|---|---|
| T1 | **Unsupplied item:** if the restaurant cannot supply an item after the order is placed (marks it unavailable), the customer is refunded that item's price and its tax, the restaurant is not paid for it, and its commission for those units is reversed. The restaurant bears the cost of marking an item unavailable. | Samivan, 2026-10-29 (Q1) | [refund-approval-plan.md](../07-Roadmap/refund-approval-plan.md), "Group refunds (2b.7)", G-8 |
| T2 | **Declined order:** a restaurant decline refunds the customer in full for that restaurant's order; the restaurant is not paid for it. | Refund design D1 to D3, 2026-10-28; 2b.4 L-14 | [schedule-2b4-order-group-plan.md](../07-Roadmap/schedule-2b4-order-group-plan.md) |
| T3 | **Cancel freeze:** once the restaurant (or a Ninjasu admin) accepts the order, the customer can no longer cancel and no refund is owed; the restaurant is then paid for the order. | Samivan, 2026-10-25 (2b.4 decision 6) | 2b.4 plan, L-14 |
| T4 | **Late delivery:** if the order has not arrived by the slot start plus the grace period (default 15 minutes), the customer may cancel that order and is refunded; the restaurant is not paid for it. Whether the restaurant is paid when the delay was Ninjasu's own is not decided. | Samivan, 2026-10-25 (2b.4 decision 9) | 2b.4 plan, L-17 |
| T5 | **Refunds are approved by Ninjasu:** a platform admin approves every refund for now; the restaurant cannot issue or block a refund. Customers are told refunds arrive within 24 hours of approval. | Samivan, 2026-10-28 (D1) | refund-approval-plan.md |
| T6 | **Money path:** the customer pays Ninjasu's account; Ninjasu refunds the customer and pays the restaurant. The restaurant never refunds directly. | architecture, Schedule is single-merchant | 2b.4 plan, 2b.8 |
| T7 | **Commission:** a slab on the online price after discount; GST on the commission is borne by the restaurant and deducted on the payout invoice. | 2b.3 final scope, 2026-10-23 | [schedule-implementation-order.md](../07-Roadmap/schedule-implementation-order.md) row 2b.3 |
| T8 | **Commission changes** take effect by notice on a stated date (at least 24 hours), not by the restaurant's approval. | Samivan, 2026-10 (rate cards) | [commission-rate-cards-plan.md](../07-Roadmap/commission-rate-cards-plan.md) |
| T9 | **Online price cap:** the restaurant's online price may not exceed the dine-in price by more than the platform cap (10% at launch); only Ninjasu changes the dine-in price. | Samivan, 2026-10-18 (2b.12) | schedule-implementation-order.md row 2b.12 |
| T10 | **Delivery and packaging fees** belong to Ninjasu, never to a restaurant; they are not part of the restaurant's payout or refund deduction. | 2b.3 / 2b.4 | 2b.4 plan |

## Not decided yet (do not put in the contract until decided)
- Whether the restaurant is paid when a late delivery is caused by Ninjasu's rider (T4).
- Dispute process when a restaurant says an item was never marked unavailable (T1): who decides and in what time. Needs the audit row the 2b.10 action will write.
- GST credit-note issuer for a partial refund (CA).
