;; SkillBounty Reputation System
;; Manages user reputation points and staking mechanisms
;;
;; Error codes:
;; u500 -> INSUFFICIENT_REPUTATION
;; u501 -> INSUFFICIENT_STAKE
;; u502 -> INVALID_AMOUNT
;; u503 -> STAKE_NOT_FOUND

;; Storage
(define-map reputation principal uint)
(define-map staked-reputation principal uint)

;; Events
(define-private (emit-rep-change (user principal) (amount uint) (operation (string-ascii 10)))
  (print {event: "reputation-change", user: user, amount: amount, operation: operation}))

(define-private (emit-stake-change (user principal) (amount uint) (operation (string-ascii 10)))
  (print {event: "stake-change", user: user, amount: amount, operation: operation}))

;; Internal functions
(define-private (get-reputation-internal (user principal))
  (default-to u0 (map-get? reputation user)))

(define-private (get-staked-reputation-internal (user principal))
  (default-to u0 (map-get? staked-reputation user)))

;; Public functions
(define-public (add-rep (user principal) (amount uint))
  (begin
    (asserts! (> amount u0) (err u502))
    (let ((current-rep (get-reputation-internal user)))
      (map-set reputation user (+ current-rep amount))
      (emit-rep-change user amount "add")
      (ok (+ current-rep amount)))))

(define-public (sub-rep (user principal) (amount uint))
  (begin
    (asserts! (> amount u0) (err u502))
    (let ((current-rep (get-reputation-internal user)))
      (asserts! (>= current-rep amount) (err u500))
      (map-set reputation user (- current-rep amount))
      (emit-rep-change user amount "sub")
      (ok (- current-rep amount)))))

(define-public (stake-rep (amount uint))
  (let ((current-rep (get-reputation-internal tx-sender))
        (current-stake (get-staked-reputation-internal tx-sender)))
    (asserts! (> amount u0) (err u502))
    (asserts! (>= current-rep amount) (err u500))

    ;; Move reputation from available to staked
    (map-set reputation tx-sender (- current-rep amount))
    (map-set staked-reputation tx-sender (+ current-stake amount))

    (emit-stake-change tx-sender amount "stake")
    (ok (+ current-stake amount))))

(define-public (unstake-rep (amount uint))
  (let ((current-rep (get-reputation-internal tx-sender))
        (current-stake (get-staked-reputation-internal tx-sender)))
    (asserts! (> amount u0) (err u502))
    (asserts! (>= current-stake amount) (err u501))

    ;; Move reputation from staked back to available
    (map-set reputation tx-sender (+ current-rep amount))
    (map-set staked-reputation tx-sender (- current-stake amount))

    (emit-stake-change tx-sender amount "unstake")
    (ok (- current-stake amount))))

;; Slash staked reputation (used by dispute resolution)
(define-public (slash-stake (user principal) (amount uint))
  (let ((current-stake (get-staked-reputation-internal user)))
    (asserts! (>= current-stake amount) (err u501))
    (map-set staked-reputation user (- current-stake amount))
    (emit-stake-change user amount "slash")
    (ok (- current-stake amount))))

;; Read-only functions
(define-read-only (get-rep (user principal))
  (get-reputation-internal user))

(define-read-only (get-staked-rep (user principal))
  (get-staked-reputation-internal user))

(define-read-only (get-total-rep (user principal))
  (+ (get-reputation-internal user) (get-staked-reputation-internal user)))

(define-read-only (get-voting-power (user principal))
  ;; Voting power is reputation + staked reputation
  (+ (get-reputation-internal user) (get-staked-reputation-internal user)))