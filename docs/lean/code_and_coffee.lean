variables (P Q S : Prop)
-- P = "Dragons exist"
-- Q = "Unicorns exist"
-- S = "Goblins exist"
-- <dead dragon> : P

theorem p_and_q (hP : P) (hQ : Q) : P ∧ Q := and.intro hP hQ
theorem p_and_q_implies_p (h : P ∧ Q) : P := and.left h
theorem p_and_q_implies_q (h : P ∧ Q) : Q := and.right h
theorem p_and_q_implies_q_and_p (h : P ∧ Q) : Q ∧ P := and.intro (and.right h) (and.left h)

theorem p_implies_p_or_q (hP : P) : P ∨ Q := or.inl hP
theorem q_implies_p_or_q (hQ : Q) : P ∨ Q := or.inr hQ
theorem p_or_q_implies_q_or_p (h : P ∨ Q) : Q ∨ P :=
or.elim h (λ hP : P, or.inr hP) (λ hQ : Q, or.inl hQ)

theorem modus_ponens (h : P → Q) (hP : P) : Q := h hP

-- P → Q → S
-- P → (Q → S)
-- P ∧ Q → S
example (h : P → Q → S) (hP : P) (hQ : Q) : S :=
have hQS : Q → S, from h hP,
hQS hQ


def alwaysTrue : true := trivial
-- _ : False
-- def alwaysFalse : false := _

-- → = "not" \n
-- →P
-- P → false
-- "if dragons existing implies unicorns must exist,
-- and unicorns don't exist, then dragons can't exist"

theorem contrapositive (hPQ : P → Q) (hnQ : Q → false) : P → false :=
λ hP : P,
have hQ : Q, from hPQ hP,
hnQ hQ

theorem explode (hP : P) (hnP : P → false) : Q :=
false.elim (hnP hP)

theorem lem : P ∨ false := or.inl (sorry : P)

-- ↔
theorem and_swap : (P ∧ Q) ↔ (Q ∧ P) :=
have forwards : (P ∧ Q) → (Q ∧ P), from
λ (h : P ∧ Q), and.intro (and.right h) (and.left h),
have backwards : (Q ∧ P) → (P ∧ Q), from
λ (h : Q ∧ P), and.intro (and.right h) (and.left h),
iff.intro forwards backwards

theorem and_swap_tactic : (P ∧ Q) ↔ (Q ∧ P) :=
iff.intro
(λ h, and.intro (and.right h) (and.left h))
(λ h, and.intro (and.right h) (and.left h))

theorem discrete : ((P → Q) → (Q → S)) ↔ (Q → S) :=
iff.intro
(λ h, λ hQ, h (λ hp : P, hQ) hQ)
(λ hQS, λ hPQ, hQS)

-- x → y
-- Eq.refl 0 : 0 = 0
-- Rq.refl x : x = x
-- : 1  = 0
-- Eq.refl 0 : 0 = 0
-- Eq.refl 1 : 1 = 1

-- 2 + 2 = 4
-- 4 = 4
-- Eq.refl 4
theorem twoPlusTwo : (2 + 2 : nat) = 4 := eq.refl 4

-- uocsclub.net/lean
