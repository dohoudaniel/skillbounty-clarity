;; SkillBounty Platform Credits (SIP-010 Fungible Token)
;; Mintable credits used for bounty payments and platform fees
;;
;; Error codes:
;; u100 -> INSUFFICIENT_BALANCE
;; u101 -> UNAUTHORIZED
;; u102 -> INVALID_AMOUNT

;; SIP-010 Trait Definition
(define-trait sip-010-trait (
    (transfer
        (uint principal principal (optional (buff 34)))
        (response bool uint)
    )
    (get-name
        ()
        (response (string-ascii 32) uint)
    )
    (get-symbol
        ()
        (response (string-ascii 32) uint)
    )
    (get-decimals
        ()
        (response uint uint)
    )
    (get-balance
        (principal)
        (response uint uint)
    )
    (get-total-supply
        ()
        (response uint uint)
    )
    (get-token-uri
        ()
        (response (optional (string-utf8 256)) uint)
    )
))

(define-fungible-token credit)

;; Storage
(define-data-var contract-owner principal tx-sender)
(define-data-var total-supply uint u0)

;; Events
(define-private (emit-mint
        (to principal)
        (amount uint)
    )
    (print {
        event: "mint",
        to: to,
        amount: amount,
    })
)

(define-private (emit-transfer
        (from principal)
        (to principal)
        (amount uint)
    )
    (print {
        event: "transfer",
        from: from,
        to: to,
        amount: amount,
    })
)

;; SIP-010 Functions
(define-read-only (get-name)
    (ok "SkillBounty Credit")
)

(define-read-only (get-symbol)
    (ok "SBC")
)

(define-read-only (get-decimals)
    (ok u6)
)

(define-read-only (get-balance (account principal))
    (ok (ft-get-balance credit account))
)

(define-read-only (get-total-supply)
    (ok (var-get total-supply))
)

(define-read-only (get-token-uri)
    (ok (some "https://skillbounty.io/token-metadata.json"))
)

(define-public (transfer
        (amount uint)
        (from principal)
        (to principal)
        (memo (optional (buff 34)))
    )
    (begin
        (asserts! (is-eq from tx-sender) (err u101))
        (asserts! (> amount u0) (err u102))
        (try! (ft-transfer? credit amount from to))
        (emit-transfer from to amount)
        (ok true)
    )
)

;; Admin Functions
(define-public (mint
        (amount uint)
        (to principal)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u101))
        (asserts! (> amount u0) (err u102))
        (try! (ft-mint? credit amount to))
        (var-set total-supply (+ (var-get total-supply) amount))
        (emit-mint to amount)
        (ok true)
    )
)

(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u101))
        (var-set contract-owner new-owner)
        (ok true)
    )
)

;; Read-only getters
(define-read-only (get-contract-owner)
    (var-get contract-owner)
)
