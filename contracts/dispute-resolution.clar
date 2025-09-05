;; SkillBounty Dispute Resolution System
;; Handles disputes for bounty submissions with community voting
;;
;; Error codes:
;; u800 -> DISPUTE_NOT_FOUND
;; u801 -> UNAUTHORIZED
;; u802 -> DISPUTE_ALREADY_EXISTS
;; u803 -> VOTING_PERIOD_ENDED
;; u804 -> VOTING_PERIOD_ACTIVE
;; u805 -> ALREADY_VOTED
;; u806 -> INSUFFICIENT_STAKE
;; u807 -> INVALID_VOTE

;; Dispute status constants
(define-constant DISPUTE_ACTIVE u0)
(define-constant DISPUTE_RESOLVED_FOR_CREATOR u1)
(define-constant DISPUTE_RESOLVED_FOR_CONTRIBUTOR u2)

;; Vote options
(define-constant VOTE_FOR_CREATOR u0)
(define-constant VOTE_FOR_CONTRIBUTOR u1)

;; Storage
(define-map disputes
    uint
    {
        bounty-id: uint,
        creator: principal,
        contributor: principal,
        reason: (string-ascii 500),
        status: uint,
        created-at: uint,
        voting-ends-at: uint,
        votes-for-creator: uint,
        votes-for-contributor: uint,
        total-stake-for-creator: uint,
        total-stake-for-contributor: uint,
    }
)

(define-map dispute-votes
    {
        dispute-id: uint,
        voter: principal,
    }
    {
        vote: uint,
        stake: uint,
        block-height: uint,
    }
)

(define-data-var next-dispute-id uint u1)

;; Events
(define-private (emit-dispute-created
        (dispute-id uint)
        (bounty-id uint)
        (creator principal)
        (contributor principal)
    )
    (print {
        event: "dispute-created",
        dispute-id: dispute-id,
        bounty-id: bounty-id,
        creator: creator,
        contributor: contributor,
    })
)

(define-private (emit-vote-cast
        (dispute-id uint)
        (voter principal)
        (vote uint)
        (stake uint)
    )
    (print {
        event: "vote-cast",
        dispute-id: dispute-id,
        voter: voter,
        vote: vote,
        stake: stake,
    })
)

(define-private (emit-dispute-resolved
        (dispute-id uint)
        (winner principal)
        (resolution uint)
    )
    (print {
        event: "dispute-resolved",
        dispute-id: dispute-id,
        winner: winner,
        resolution: resolution,
    })
)

;; Public functions
(define-public (create-dispute
        (bounty-id uint)
        (contributor principal)
        (reason (string-ascii 500))
    )
    (let (
            (dispute-id (var-get next-dispute-id))
            (dispute-window (contract-call? .platform-settings get-dispute-window-blocks))
        )
        (asserts! (is-none (get-dispute-for-bounty bounty-id)) (err u802))
        (asserts! (> (len reason) u0) (err u807))

        ;; Store dispute
        (map-set disputes dispute-id {
            bounty-id: bounty-id,
            creator: tx-sender,
            contributor: contributor,
            reason: reason,
            status: DISPUTE_ACTIVE,
            created-at: stacks-block-height,
            voting-ends-at: (+ stacks-block-height dispute-window),
            votes-for-creator: u0,
            votes-for-contributor: u0,
            total-stake-for-creator: u0,
            total-stake-for-contributor: u0,
        })

        (var-set next-dispute-id (+ dispute-id u1))
        (emit-dispute-created dispute-id bounty-id tx-sender contributor)
        (ok dispute-id)
    )
)

(define-public (vote-on-dispute
        (dispute-id uint)
        (vote uint)
        (stake-amount uint)
    )
    (let (
            (dispute-data (unwrap! (map-get? disputes dispute-id) (err u800)))
            (voter-stake (contract-call? .reputation get-staked-rep tx-sender))
            (min-stake (contract-call? .platform-settings get-min-stake-to-vote))
        )
        (asserts! (is-eq (get status dispute-data) DISPUTE_ACTIVE) (err u804))
        (asserts! (< stacks-block-height (get voting-ends-at dispute-data))
            (err u803)
        )
        (asserts!
            (or (is-eq vote VOTE_FOR_CREATOR) (is-eq vote VOTE_FOR_CONTRIBUTOR))
            (err u807)
        )
        (asserts! (>= voter-stake min-stake) (err u806))
        (asserts! (>= voter-stake stake-amount) (err u806))
        (asserts! (> stake-amount u0) (err u806))
        (asserts!
            (is-none (map-get? dispute-votes {
                dispute-id: dispute-id,
                voter: tx-sender,
            }))
            (err u805)
        )

        ;; Stake reputation for voting
        (try! (contract-call? .reputation stake-rep stake-amount))

        ;; Record vote
        (map-set dispute-votes {
            dispute-id: dispute-id,
            voter: tx-sender,
        } {
            vote: vote,
            stake: stake-amount,
            block-height: stacks-block-height,
        })

        ;; Update dispute totals
        (if (is-eq vote VOTE_FOR_CREATOR)
            (map-set disputes dispute-id
                (merge dispute-data {
                    votes-for-creator: (+ (get votes-for-creator dispute-data) u1),
                    total-stake-for-creator: (+ (get total-stake-for-creator dispute-data) stake-amount),
                })
            )
            (map-set disputes dispute-id
                (merge dispute-data {
                    votes-for-contributor: (+ (get votes-for-contributor dispute-data) u1),
                    total-stake-for-contributor: (+ (get total-stake-for-contributor dispute-data)
                        stake-amount
                    ),
                })
            )
        )

        (emit-vote-cast dispute-id tx-sender vote stake-amount)
        (ok true)
    )
)

(define-public (resolve-dispute (dispute-id uint))
    (let ((dispute-data (unwrap! (map-get? disputes dispute-id) (err u800))))
        (asserts! (is-eq (get status dispute-data) DISPUTE_ACTIVE) (err u804))
        (asserts! (>= stacks-block-height (get voting-ends-at dispute-data))
            (err u804)
        )

        (let (
                (creator-stake (get total-stake-for-creator dispute-data))
                (contributor-stake (get total-stake-for-contributor dispute-data))
                (winner (if (> creator-stake contributor-stake)
                    (get creator dispute-data)
                    (get contributor dispute-data)
                ))
                (resolution (if (> creator-stake contributor-stake)
                    DISPUTE_RESOLVED_FOR_CREATOR
                    DISPUTE_RESOLVED_FOR_CONTRIBUTOR
                ))
            )
            ;; Update dispute status
            (map-set disputes dispute-id
                (merge dispute-data { status: resolution })
            )

            ;; Reward winning voters and slash losing voters
            (try! (distribute-rewards-and-penalties dispute-id))

            (emit-dispute-resolved dispute-id winner resolution)
            (ok resolution)
        )
    )
)

;; Private helper functions
(define-private (distribute-rewards-and-penalties (dispute-id uint))
    (let ((dispute-data (unwrap! (map-get? disputes dispute-id) (err u800))))
        ;; This is a simplified implementation
        ;; In a full implementation, you would iterate through all voters
        ;; and reward winners while slashing losers
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-dispute (dispute-id uint))
    (map-get? disputes dispute-id)
)

(define-read-only (get-dispute-for-bounty (bounty-id uint))
    ;; This is a simplified lookup - in practice you might want to index by bounty-id
    none
)

(define-read-only (get-vote
        (dispute-id uint)
        (voter principal)
    )
    (map-get? dispute-votes {
        dispute-id: dispute-id,
        voter: voter,
    })
)

(define-read-only (is-voting-active (dispute-id uint))
    (match (map-get? disputes dispute-id)
        dispute-data (and
            (is-eq (get status dispute-data) DISPUTE_ACTIVE)
            (< stacks-block-height (get voting-ends-at dispute-data))
        )
        false
    )
)

(define-read-only (get-next-dispute-id)
    (var-get next-dispute-id)
)
