;; SkillBounty Badge NFT (SIP-009)
;; Achievement badges minted when users reach reputation milestones
;;
;; Error codes:
;; u700 -> TOKEN_NOT_FOUND
;; u701 -> UNAUTHORIZED
;; u702 -> TOKEN_ALREADY_EXISTS
;; u703 -> MILESTONE_NOT_REACHED

(define-non-fungible-token skill-badge uint)

;; Badge types
(define-constant BADGE_NEWCOMER u1) ;; 100 rep
(define-constant BADGE_CONTRIBUTOR u2) ;; 500 rep
(define-constant BADGE_EXPERT u3) ;; 1000 rep
(define-constant BADGE_MASTER u4) ;; 2500 rep

;; Storage
(define-data-var last-token-id uint u0)
(define-map token-metadata
    uint
    {
        name: (string-ascii 50),
        description: (string-ascii 200),
        image: (string-ascii 200),
        badge-type: uint,
        earned-at: uint,
    }
)

(define-map user-badges
    principal
    (list 10 uint)
)

;; Events
(define-private (emit-badge-minted
        (token-id uint)
        (to principal)
        (badge-type uint)
    )
    (print {
        event: "badge-minted",
        token-id: token-id,
        to: to,
        badge-type: badge-type,
    })
)

;; SIP-009 Functions
(define-read-only (get-last-token-id)
    (ok (var-get last-token-id))
)

(define-read-only (get-token-uri (token-id uint))
    (ok (some "https://skillbounty.io/badge-metadata/{id}"))
)

(define-read-only (get-owner (token-id uint))
    (ok (nft-get-owner? skill-badge token-id))
)

(define-public (transfer
        (token-id uint)
        (sender principal)
        (recipient principal)
    )
    (begin
        (asserts! (is-eq tx-sender sender) (err u701))
        (nft-transfer? skill-badge token-id sender recipient)
    )
)

;; Internal badge minting logic
(define-private (get-badge-type-for-rep (reputation uint))
    (if (>= reputation u2500)
        BADGE_MASTER
        (if (>= reputation u1000)
            BADGE_EXPERT
            (if (>= reputation u500)
                BADGE_CONTRIBUTOR
                (if (>= reputation u100)
                    BADGE_NEWCOMER
                    u0
                )
            )
        )
    )
)

(define-private (get-badge-name (badge-type uint))
    (if (is-eq badge-type BADGE_NEWCOMER)
        "Newcomer"
        (if (is-eq badge-type BADGE_CONTRIBUTOR)
            "Contributor"
            (if (is-eq badge-type BADGE_EXPERT)
                "Expert"
                (if (is-eq badge-type BADGE_MASTER)
                    "Master"
                    "Unknown"
                )
            )
        )
    )
)

(define-private (get-badge-description (badge-type uint))
    (if (is-eq badge-type BADGE_NEWCOMER)
        "First steps into the SkillBounty ecosystem"
        (if (is-eq badge-type BADGE_CONTRIBUTOR)
            "Active contributor to the community"
            (if (is-eq badge-type BADGE_EXPERT)
                "Recognized expert in their field"
                (if (is-eq badge-type BADGE_MASTER)
                    "Master craftsperson and community leader"
                    "Achievement badge"
                )
            )
        )
    )
)

;; Public functions
(define-public (try-mint-milestone-badge (user principal))
    (let (
            (user-rep (contract-call? .reputation get-total-rep user))
            (badge-type (get-badge-type-for-rep user-rep))
        )
        (if (> badge-type u0)
            (mint-badge user badge-type)
            (ok false)
        )
    )
)

(define-private (mint-badge
        (to principal)
        (badge-type uint)
    )
    (let ((token-id (+ (var-get last-token-id) u1)))
        (try! (nft-mint? skill-badge token-id to))
        (var-set last-token-id token-id)

        ;; Store metadata
        (map-set token-metadata token-id {
            name: (get-badge-name badge-type),
            description: (get-badge-description badge-type),
            image: "https://skillbounty.io/badges/{badge-type}.png",
            badge-type: badge-type,
            earned-at: stacks-block-height,
        })

        ;; Update user's badge list
        (let ((current-badges (default-to (list) (map-get? user-badges to))))
            (map-set user-badges to
                (unwrap! (as-max-len? (append current-badges token-id) u10)
                    (err u702)
                ))
        )

        (emit-badge-minted token-id to badge-type)
        (ok true)
    )
)

;; Admin mint function for testing
(define-public (admin-mint
        (to principal)
        (badge-type uint)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u701))
        (asserts!
            (and (>= badge-type BADGE_NEWCOMER) (<= badge-type BADGE_MASTER))
            (err u703)
        )
        (mint-badge to badge-type)
    )
)

;; Contract owner management
(define-data-var contract-owner principal tx-sender)

(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u701))
        (var-set contract-owner new-owner)
        (ok true)
    )
)

(define-read-only (get-contract-owner)
    (var-get contract-owner)
)
