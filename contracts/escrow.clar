;; SkillBounty Escrow System
;; Manages locked funds for bounty payments
;;
;; Error codes:
;; u300 -> ESCROW_NOT_FOUND
;; u301 -> INSUFFICIENT_ESCROW
;; u302 -> UNAUTHORIZED
;; u303 -> ESCROW_ALREADY_EXISTS

;; Import token contract trait
(use-trait ft-trait .token-credit.sip-010-trait)

;; Storage
(define-map escrows
    uint
    {
        amount: uint,
        depositor: principal,
    }
)
(define-data-var next-escrow-id uint u1)

;; Events
(define-private (emit-deposit
        (escrow-id uint)
        (depositor principal)
        (amount uint)
    )
    (print {
        event: "escrow-deposit",
        escrow-id: escrow-id,
        depositor: depositor,
        amount: amount,
    })
)

(define-private (emit-release
        (escrow-id uint)
        (recipient principal)
        (amount uint)
    )
    (print {
        event: "escrow-release",
        escrow-id: escrow-id,
        recipient: recipient,
        amount: amount,
    })
)

;; Public functions
(define-public (deposit-escrow
        (bounty-id uint)
        (amount uint)
    )
    (let ((escrow-data (default-to {
            amount: u0,
            depositor: tx-sender,
        }
            (map-get? escrows bounty-id)
        )))
        (asserts! (is-eq (get amount escrow-data) u0) (err u303))
        (try! (contract-call? .token-credit transfer amount tx-sender
            (as-contract tx-sender) none
        ))
        (map-set escrows bounty-id {
            amount: amount,
            depositor: tx-sender,
        })
        (emit-deposit bounty-id tx-sender amount)
        (ok bounty-id)
    )
)

(define-public (release-to
        (bounty-id uint)
        (recipient principal)
    )
    (let ((escrow-data (unwrap! (map-get? escrows bounty-id) (err u300))))
        (asserts! (is-eq (get depositor escrow-data) tx-sender) (err u302))
        (asserts! (> (get amount escrow-data) u0) (err u301))
        (try! (as-contract (contract-call? .token-credit transfer (get amount escrow-data) tx-sender
            recipient none
        )))
        (map-delete escrows bounty-id)
        (emit-release bounty-id recipient (get amount escrow-data))
        (ok (get amount escrow-data))
    )
)

(define-public (refund-to
        (bounty-id uint)
        (refund-recipient principal)
    )
    (let ((escrow-data (unwrap! (map-get? escrows bounty-id) (err u300))))
        (asserts! (is-eq (get depositor escrow-data) tx-sender) (err u302))
        (asserts! (> (get amount escrow-data) u0) (err u301))
        (try! (as-contract (contract-call? .token-credit transfer (get amount escrow-data) tx-sender
            refund-recipient none
        )))
        (map-delete escrows bounty-id)
        (emit-release bounty-id refund-recipient (get amount escrow-data))
        (ok (get amount escrow-data))
    )
)

;; Read-only functions
(define-read-only (get-escrow-amount (bounty-id uint))
    (match (map-get? escrows bounty-id)
        escrow-data (get amount escrow-data)
        u0
    )
)

(define-read-only (get-escrow-depositor (bounty-id uint))
    (match (map-get? escrows bounty-id)
        escrow-data (some (get depositor escrow-data))
        none
    )
)
