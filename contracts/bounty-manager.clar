;; SkillBounty Bounty Management
;; Core bounty creation, assignment, submission, and approval system
;;
;; Error codes:
;; u400 -> BOUNTY_NOT_FOUND
;; u401 -> UNAUTHORIZED
;; u402 -> BOUNTY_EXPIRED
;; u403 -> BOUNTY_ALREADY_ASSIGNED
;; u404 -> BOUNTY_NOT_ASSIGNED
;; u405 -> INSUFFICIENT_REPUTATION
;; u406 -> INVALID_STATUS
;; u407 -> SUBMISSION_NOT_FOUND

;; Bounty status constants
(define-constant STATUS_OPEN u0)
(define-constant STATUS_ASSIGNED u1)
(define-constant STATUS_SUBMITTED u2)
(define-constant STATUS_COMPLETED u3)
(define-constant STATUS_CANCELLED u4)

;; Storage
(define-map bounties
    uint
    {
        creator: principal,
        assigned-to: (optional principal),
        reward-amount: uint,
        required-rep: uint,
        deadline-block: uint,
        status: uint,
        submission-hash: (optional (buff 32)),
        skill-category: (string-ascii 50),
    }
)

(define-data-var next-bounty-id uint u1)

;; Events
(define-private (emit-bounty-created
        (bounty-id uint)
        (creator principal)
        (reward uint)
    )
    (print {
        event: "bounty-created",
        bounty-id: bounty-id,
        creator: creator,
        reward: reward,
    })
)

(define-private (emit-bounty-assigned
        (bounty-id uint)
        (contributor principal)
    )
    (print {
        event: "bounty-assigned",
        bounty-id: bounty-id,
        contributor: contributor,
    })
)

(define-private (emit-submission
        (bounty-id uint)
        (contributor principal)
        (hash (buff 32))
    )
    (print {
        event: "submission",
        bounty-id: bounty-id,
        contributor: contributor,
        hash: hash,
    })
)

(define-private (emit-bounty-completed
        (bounty-id uint)
        (contributor principal)
        (reward uint)
    )
    (print {
        event: "bounty-completed",
        bounty-id: bounty-id,
        contributor: contributor,
        reward: reward,
    })
)

;; Public functions
(define-public (create-bounty
        (reward-amount uint)
        (required-rep uint)
        (deadline-blocks uint)
        (skill-category (string-ascii 50))
    )
    (let (
            (bounty-id (var-get next-bounty-id))
            (creator-rep (contract-call? .reputation get-rep tx-sender))
            (min-rep (contract-call? .platform-settings get-min-rep-to-create))
        )
        (asserts! (>= creator-rep min-rep) (err u405))
        (asserts! (> reward-amount u0) (err u406))
        (asserts! (> deadline-blocks u0) (err u406))

        ;; Deposit to escrow
        (try! (contract-call? .escrow deposit-escrow bounty-id reward-amount))

        ;; Store bounty
        (map-set bounties bounty-id {
            creator: tx-sender,
            assigned-to: none,
            reward-amount: reward-amount,
            required-rep: required-rep,
            deadline-block: (+ stacks-block-height deadline-blocks),
            status: STATUS_OPEN,
            submission-hash: none,
            skill-category: skill-category,
        })

        (var-set next-bounty-id (+ bounty-id u1))
        (emit-bounty-created bounty-id tx-sender reward-amount)
        (ok bounty-id)
    )
)

(define-public (assign-bounty
        (bounty-id uint)
        (contributor principal)
    )
    (let (
            (bounty-data (unwrap! (map-get? bounties bounty-id) (err u400)))
            (contributor-rep (contract-call? .reputation get-rep contributor))
        )
        (asserts! (is-eq (get creator bounty-data) tx-sender) (err u401))
        (asserts! (is-eq (get status bounty-data) STATUS_OPEN) (err u403))
        (asserts! (>= contributor-rep (get required-rep bounty-data)) (err u405))
        (asserts! (< stacks-block-height (get deadline-block bounty-data))
            (err u402)
        )

        (map-set bounties bounty-id
            (merge bounty-data {
                assigned-to: (some contributor),
                status: STATUS_ASSIGNED,
            })
        )

        (emit-bounty-assigned bounty-id contributor)
        (ok true)
    )
)

(define-public (submit-work
        (bounty-id uint)
        (submission-hash (buff 32))
    )
    (let ((bounty-data (unwrap! (map-get? bounties bounty-id) (err u400))))
        (asserts!
            (is-eq (unwrap! (get assigned-to bounty-data) (err u404)) tx-sender)
            (err u401)
        )
        (asserts! (is-eq (get status bounty-data) STATUS_ASSIGNED) (err u406))
        (asserts! (< stacks-block-height (get deadline-block bounty-data))
            (err u402)
        )

        (map-set bounties bounty-id
            (merge bounty-data {
                status: STATUS_SUBMITTED,
                submission-hash: (some submission-hash),
            })
        )

        (emit-submission bounty-id tx-sender submission-hash)
        (ok true)
    )
)

(define-public (approve-and-complete (bounty-id uint))
    (let (
            (bounty-data (unwrap! (map-get? bounties bounty-id) (err u400)))
            (contributor (unwrap! (get assigned-to bounty-data) (err u404)))
        )
        (asserts! (is-eq (get creator bounty-data) tx-sender) (err u401))
        (asserts! (is-eq (get status bounty-data) STATUS_SUBMITTED) (err u406))
        (asserts! (is-some (get submission-hash bounty-data)) (err u407))

        ;; Release escrow to contributor
        (try! (contract-call? .escrow release-to bounty-id contributor))

        ;; Update status
        (map-set bounties bounty-id
            (merge bounty-data { status: STATUS_COMPLETED })
        )

        ;; Add reputation to contributor
        (try! (contract-call? .reputation add-rep contributor u50))

        ;; Try to mint badge if milestone reached
        (try! (contract-call? .badge-nft try-mint-milestone-badge contributor))

        (emit-bounty-completed bounty-id contributor
            (get reward-amount bounty-data)
        )
        (ok true)
    )
)

(define-public (cancel-bounty (bounty-id uint))
    (let ((bounty-data (unwrap! (map-get? bounties bounty-id) (err u400))))
        (asserts! (is-eq (get creator bounty-data) tx-sender) (err u401))
        (asserts!
            (or
                (is-eq (get status bounty-data) STATUS_OPEN)
                (is-eq (get status bounty-data) STATUS_ASSIGNED)
            )
            (err u406)
        )

        ;; Refund escrow to creator
        (try! (contract-call? .escrow refund-to bounty-id tx-sender))

        ;; Update status
        (map-set bounties bounty-id
            (merge bounty-data { status: STATUS_CANCELLED })
        )

        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-bounty (bounty-id uint))
    (map-get? bounties bounty-id)
)

(define-read-only (get-next-bounty-id)
    (var-get next-bounty-id)
)

(define-read-only (is-bounty-expired (bounty-id uint))
    (match (map-get? bounties bounty-id)
        bounty-data (>= stacks-block-height (get deadline-block bounty-data))
        true
    )
)
