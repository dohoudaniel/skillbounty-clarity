;; SkillBounty Endorsement System
;; Allows users to endorse each other's skills for small reputation rewards
;;
;; Error codes:
;; u600 -> SELF_ENDORSEMENT_NOT_ALLOWED
;; u601 -> ALREADY_ENDORSED
;; u602 -> INVALID_SKILL_CATEGORY

;; Storage
(define-map endorsements
    {
        endorser: principal,
        endorsed: principal,
        skill: (string-ascii 50),
    }
    {
        message: (string-ascii 500),
        block-height: uint,
    }
)

(define-map user-endorsement-count
    principal
    uint
)
(define-map skill-endorsement-count
    {
        user: principal,
        skill: (string-ascii 50),
    }
    uint
)

;; Constants
(define-constant ENDORSEMENT_REP_REWARD u10)

;; Events
(define-private (emit-endorsement
        (endorser principal)
        (endorsed principal)
        (skill (string-ascii 50))
    )
    (print {
        event: "endorsement",
        endorser: endorser,
        endorsed: endorsed,
        skill: skill,
    })
)

;; Public functions
(define-public (endorse-user
        (skill (string-ascii 50))
        (target-principal principal)
        (message (string-ascii 500))
    )
    (let ((endorsement-key {
            endorser: tx-sender,
            endorsed: target-principal,
            skill: skill,
        }))
        (asserts! (not (is-eq tx-sender target-principal)) (err u600))
        (asserts! (> (len skill) u0) (err u602))
        (asserts! (is-none (map-get? endorsements endorsement-key)) (err u601))

        ;; Store endorsement
        (map-set endorsements endorsement-key {
            message: message,
            block-height: stacks-block-height,
        })

        ;; Update counters
        (let (
                (current-total (default-to u0 (map-get? user-endorsement-count target-principal)))
                (current-skill (default-to u0
                    (map-get? skill-endorsement-count {
                        user: target-principal,
                        skill: skill,
                    })
                ))
            )
            (map-set user-endorsement-count target-principal (+ current-total u1))
            (map-set skill-endorsement-count {
                user: target-principal,
                skill: skill,
            }
                (+ current-skill u1)
            )
        )

        ;; Award reputation to endorsed user
        (try! (contract-call? .reputation add-rep target-principal
            ENDORSEMENT_REP_REWARD
        ))

        (emit-endorsement tx-sender target-principal skill)
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-endorsement
        (endorser principal)
        (endorsed principal)
        (skill (string-ascii 50))
    )
    (map-get? endorsements {
        endorser: endorser,
        endorsed: endorsed,
        skill: skill,
    })
)

(define-read-only (get-endorsements-for (user principal))
    (default-to u0 (map-get? user-endorsement-count user))
)

(define-read-only (get-skill-endorsements
        (user principal)
        (skill (string-ascii 50))
    )
    (default-to u0
        (map-get? skill-endorsement-count {
            user: user,
            skill: skill,
        })
    )
)

(define-read-only (has-endorsed
        (endorser principal)
        (endorsed principal)
        (skill (string-ascii 50))
    )
    (is-some (map-get? endorsements {
        endorser: endorser,
        endorsed: endorsed,
        skill: skill,
    }))
)
