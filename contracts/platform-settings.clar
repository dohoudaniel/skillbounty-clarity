;; SkillBounty Platform Settings
;; Stores admin configuration and global constants
;;
;; Error codes:
;; u200 -> UNAUTHORIZED
;; u201 -> INVALID_VALUE

(define-data-var admin principal tx-sender)
(define-data-var fee-percent uint u5) ;; 5% platform fee
(define-data-var dispute-window-blocks uint u144) ;; ~24 hours
(define-data-var min-rep-to-create uint u100) ;; minimum reputation to create bounties
(define-data-var min-stake-to-vote uint u1000) ;; minimum stake to participate in disputes

;; Admin functions
(define-public (set-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u200))
    (var-set admin new-admin)
    (ok true)))

(define-public (set-fee-percent (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u200))
    (asserts! (<= new-fee u20) (err u201)) ;; Max 20% fee
    (var-set fee-percent new-fee)
    (ok true)))

(define-public (set-dispute-window-blocks (new-window uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u200))
    (asserts! (> new-window u0) (err u201))
    (var-set dispute-window-blocks new-window)
    (ok true)))

(define-public (set-min-rep-to-create (new-min uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u200))
    (var-set min-rep-to-create new-min)
    (ok true)))

(define-public (set-min-stake-to-vote (new-min uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u200))
    (asserts! (> new-min u0) (err u201))
    (var-set min-stake-to-vote new-min)
    (ok true)))

;; Read-only getters
(define-read-only (get-admin)
  (var-get admin))

(define-read-only (get-fee-percent)
  (var-get fee-percent))

(define-read-only (get-dispute-window-blocks)
  (var-get dispute-window-blocks))

(define-read-only (get-min-rep-to-create)
  (var-get min-rep-to-create))

(define-read-only (get-min-stake-to-vote)
  (var-get min-stake-to-vote))