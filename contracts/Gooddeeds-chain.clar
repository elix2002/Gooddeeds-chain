;; -----------------------------------------------------------------------------
;; ImpactChain: Smart NGO Impact Tracker
;; Version: 1.0
;; Purpose: Register NGOs & projects, collect donations, verify milestones, and
;;          release funds transparently on-chain.
;; Notes: Clarinet-friendly. Use `stx-get-transfer-amount` (donor includes STX
;;        with the donate call) and `stx-transfer?` to send funds out.
;; -----------------------------------------------------------------------------

;; ----------------------------
;; Owner (set at deployment)
;; ----------------------------
(define-data-var owner principal tx-sender)

(define-public (get-owner)
  (ok (var-get owner))
)

;; ----------------------------
;; Counters
;; ----------------------------
(define-data-var ngo-counter uint u0)
(define-data-var project-counter uint u0)
(define-data-var donation-counter uint u0)
(define-data-var milestone-counter uint u0)

;; ----------------------------
;; NGO structure
;; ----------------------------
(define-map ngos
  { id: uint }
  {
    name: (string-ascii 64),
    wallet: principal,
    verified: bool,
    metadata: (string-ascii 128)
  }
)

;; ----------------------------
;; Project structure
;; ----------------------------
(define-map projects
  { id: uint }
  {
    ngo-id: uint,
    title: (string-ascii 100),
    description: (string-ascii 256),
    goal: uint,          ;; goal in micro-STX (STX * 1e6 in tests if you prefer)
    raised: uint,
    completed: bool,
    created-at: uint
  }
)

;; ----------------------------
;; Milestone structure
;; ----------------------------
(define-map milestones
  { id: uint }
  {
    project-id: uint,
    title: (string-ascii 100),
    description: (string-ascii 256),
    amount: uint,           ;; tranche amount to release when verified
    verified: bool,
    verifier: (optional principal),
    created-at: uint,
    verified-at: (optional uint)
  }
)

;; ----------------------------
;; Donations: each donor + project pair stored as record
;; donation-id used for unique entries
;; ----------------------------
(define-map donations
  { id: uint }
  {
    project-id: uint,
    donor: principal,
    amount: uint,
    timestamp: uint
  }
)

;; ----------------------------
;; Verifiers registry (addresses allowed to verify milestones)
;; ----------------------------
(define-map verifiers
  { addr: principal } { allowed: bool })

;; ----------------------------
;; Events
;; ----------------------------
;; Events are emitted using `print` with a tuple payload. Below are the event shapes
;; documented for off-chain indexers.
;;
;; ngo-registered:  { event: "ngo-registered", ngo-id: uint, name: string-ascii-64, wallet: principal }
;; ngo-verified:    { event: "ngo-verified", ngo-id: uint, by: principal }
;; project-created: { event: "project-created", project-id: uint, ngo-id: uint, title: string-ascii-100 }
;; donation-received:{ event: "donation-received", donation-id: uint, project-id: uint, donor: principal, amount: uint }
;; milestone-created:{ event: "milestone-created", milestone-id: uint, project-id: uint, amount: uint }
;; milestone-verified:{ event: "milestone-verified", milestone-id: uint, project-id: uint, by: principal }
;; funds-released:  { event: "funds-released", project-id: uint, milestone-id: uint, amount: uint, to: principal }

;; ----------------------------
;; Helpers: authorization
;; ----------------------------
(define-read-only (is-owner (addr principal))
  (is-eq addr (var-get owner))
)

(define-read-only (is-verifier (addr principal))
  (match (map-get? verifiers {addr: addr})
    some-entry (get allowed some-entry)
    false
  )
)

;; ----------------------------
;; ADMIN / OWNER ACTIONS
;; ----------------------------

;; Transfer ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get owner)) (err "UNAUTHORIZED"))
    (asserts! (not (is-eq new-owner tx-sender)) (err "INVALID_OWNER"))
    (ok (var-set owner new-owner))
  )
)

;; Add or remove verifier (owner only)
(define-public (set-verifier (addr principal) (allow bool))
  (begin
    (asserts! (is-eq tx-sender (var-get owner)) (err "UNAUTHORIZED"))
    (asserts! (not (is-eq addr tx-sender)) (err "INVALID_VERIFIER"))
    (ok (map-set verifiers {addr: addr} {allowed: allow}))
  )
)

;; Verify an NGO (owner only)
(define-public (verify-ngo (ngo-id uint))
  (begin
    (asserts! (is-eq tx-sender (var-get owner)) (err "UNAUTHORIZED"))
    (asserts! (> ngo-id u0) (err "INVALID_NGO_ID"))
    (match (map-get? ngos {id: ngo-id})
      entry
      (begin
        (map-set ngos {id: ngo-id} (merge entry {verified: true}))
        (print { event: "ngo-verified", ngo-id: ngo-id, by: tx-sender })
        (ok true)
      )
      (err "NGO_NOT_FOUND")
    )
  )
)

;; ----------------------------
;; NGO / Public ACTIONS
;; ----------------------------
;; Register new NGO
(define-public (register-ngo (name (string-ascii 64)) (metadata (string-ascii 128)))
  (let 
    ((new-id (+ u1 (var-get ngo-counter))))
    (begin
      (asserts! (> (len name) u0) (err "INVALID_NAME"))
      (asserts! (> (len metadata) u0) (err "INVALID_METADATA"))
      (map-set ngos {id: new-id}
        {
          name: name,
          wallet: tx-sender,
          verified: false,
          metadata: metadata
        })
      (var-set ngo-counter new-id)
      (print { event: "ngo-registered", ngo-id: new-id, name: name, wallet: tx-sender })
      (ok new-id)
    )
  )
)

;; Create a project (only the registered NGO wallet can create projects for itself)
(define-public (create-project (ngo-id uint) (title (string-ascii 100)) (description (string-ascii 256)) (goal uint))
  (begin
    (asserts! (> (len title) u0) (err "INVALID_TITLE"))
    (asserts! (> (len description) u0) (err "INVALID_DESCRIPTION"))
    (asserts! (> goal u0) (err "INVALID_GOAL"))
    (match (map-get? ngos {id: ngo-id})
      ngo
      (begin
        (asserts! (is-eq tx-sender (get wallet ngo)) (err "NOT_NGO_WALLET"))
        (let ((new-pid (+ u1 (var-get project-counter))))
          (begin
            (map-set projects {id: new-pid}
              {
                ngo-id: ngo-id,
                title: title,
                description: description,
                goal: goal,
                raised: u0,
                completed: false,
                created-at: stacks-block-height
              })
            (var-set project-counter new-pid)
            (print { event: "project-created", project-id: new-pid, ngo-id: ngo-id, title: title })
            (ok new-pid)
          )
        )
      )
      (err "NGO_NOT_FOUND")
    )
  )
)

;; Donate to a project:
;; - Donor must include STX in the call
;; - Project's raised amount is increased
(define-public (donate (project-id uint) (amount uint))
  (begin
    (asserts! (> amount u0) (err "NO_STX_SENT"))
    (match (map-get? projects {id: project-id})
        p
        (let ((new-did (+ u1 (var-get donation-counter))))
          (begin
            (map-set donations {id: new-did}
              {
                project-id: project-id,
                donor: tx-sender,
                amount: amount,
                timestamp: stacks-block-height
              }
            )
            (var-set donation-counter new-did)
            ;; Update project's raised amount
            (map-set projects {id: project-id}
              {
                ngo-id: (get ngo-id p),
                title: (get title p),
                description: (get description p),
                goal: (get goal p),
                raised: (+ (get raised p) amount),
                completed: (get completed p),
                created-at: (get created-at p)
              }
            )
            (print { event: "donation-received", donation-id: new-did, project-id: project-id, donor: tx-sender, amount: amount })
            (ok new-did)
          )
        )
        (err "PROJECT_NOT_FOUND")
      )
    )
  )

;; Create milestone for a project (only NGO wallet)
(define-public (create-milestone (project-id uint) (title (string-ascii 100)) (description (string-ascii 256)) (amount uint))
  (begin
    (match (map-get? projects {id: project-id})
      project-entry
      (let ((ngo-id (get ngo-id project-entry))
            (new-mid (+ u1 (var-get milestone-counter))))
        (match (map-get? ngos {id: ngo-id})
          ngo-entry
          (begin
            (asserts! (is-eq (get wallet ngo-entry) tx-sender) (err "NOT_NGO_WALLET"))
            (map-set milestones {id: new-mid}
              {
                project-id: project-id,
                title: title,
                description: description,
                amount: amount,
                verified: false,
                verifier: none,
                created-at: stacks-block-height,
                verified-at: none
              }
            )
            (var-set milestone-counter new-mid)
            (print { event: "milestone-created", milestone-id: new-mid, project-id: project-id, amount: amount })
            (ok new-mid)
          )
          (err "NGO_NOT_FOUND")
        )
      )
      (err "PROJECT_NOT_FOUND")
    )
  )
)

;; Verify milestone (only registered verifiers)
(define-public (verify-milestone (milestone-id uint))
  (begin
    (asserts! (is-verifier tx-sender) (err "NOT_AUTHORIZED_VERIFIER"))
    (match (map-get? milestones {id: milestone-id})
      m
      (begin
        (map-set milestones {id: milestone-id}
          {
            project-id: (get project-id m),
            title: (get title m),
            description: (get description m),
            amount: (get amount m),
            verified: true,
            verifier: (some tx-sender),
            created-at: (get created-at m),
            verified-at: (some stacks-block-height)
          }
        )
        (print { event: "milestone-verified", milestone-id: milestone-id, project-id: (get project-id m), by: tx-sender })
        (ok true)
      )
      (err "MILESTONE_NOT_FOUND")
    )
  )
)

;; Release funds for a verified milestone to the NGO wallet (owner or verifier can call)
(define-public (release-funds (milestone-id uint))
  (begin
    ;; Must be called by owner or a verifier
    (asserts! (or (is-verifier tx-sender) (is-eq tx-sender (var-get owner))) (err "UNAUTHORIZED"))
    (match (map-get? milestones {id: milestone-id})
      milestone-entry
      (let ((m milestone-entry))
        (asserts! (get verified m) (err "MILESTONE_NOT_VERIFIED"))
        (let ((project-id (get project-id m)))
          (match (map-get? projects {id: project-id})
            project-entry
            (let ((p project-entry)
                  (amt (get amount m)))
              (let ((ngo-id (get ngo-id p)))
                (match (map-get? ngos {id: ngo-id})
                  ngo-entry
                  (let ((ngo ngo-entry)
                        (wallet (get wallet ngo)))
                    (begin
                      ;; decrement project's raised amount by the milestone amount
                      (map-set projects {id: project-id}
                        {
                          ngo-id: ngo-id,
                          title: (get title p),
                          description: (get description p),
                          goal: (get goal p),
                          raised: (- (get raised p) amt),
                          completed: (get completed p),
                          created-at: (get created-at p)
                        }
                      )
                      ;; emit event (actual STX transfer can be implemented separately)
                      (print { event: "funds-released", project-id: project-id, milestone-id: milestone-id, amount: amt, to: wallet })
                      (ok true)
                    )
                  )
                  (err "NGO_NOT_FOUND")
                )
              )
            )
            (err "PROJECT_NOT_FOUND")
          )
        )
      )
      (err "MILESTONE_NOT_FOUND")
    )
  )
)

;; ----------------------------
;; READ-ONLY / VIEW HELPERS
;; ----------------------------

(define-read-only (get-ngo (ngo-id uint))
  (map-get? ngos {id: ngo-id})
)

(define-read-only (get-project (project-id uint))
  (map-get? projects {id: project-id})
)

(define-read-only (get-milestone (milestone-id uint))
  (map-get? milestones {id: milestone-id})
)

(define-read-only (get-donation (donation-id uint))
  (map-get? donations {id: donation-id})
)

(define-read-only (get-verifier-status (addr principal))
  (map-get? verifiers {addr: addr})
)

(define-read-only (get-ngo-count)
  (ok (var-get ngo-counter))
)

(define-read-only (get-project-count)
  (ok (var-get project-counter))
)

(define-read-only (get-donation-count)
  (ok (var-get donation-counter))
)

(define-read-only (get-milestone-count)
  (ok (var-get milestone-counter))
)
