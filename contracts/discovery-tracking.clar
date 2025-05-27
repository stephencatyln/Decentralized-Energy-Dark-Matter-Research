;; Discovery Tracking Contract
;; Records and tracks dark matter research breakthroughs

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u500))
(define-constant ERR_DISCOVERY_NOT_FOUND (err u501))
(define-constant ERR_INVALID_SIGNIFICANCE (err u502))
(define-constant ERR_ALREADY_VERIFIED (err u503))

;; Significance levels
(define-constant SIGNIFICANCE_MINOR u1)
(define-constant SIGNIFICANCE_MODERATE u2)
(define-constant SIGNIFICANCE_MAJOR u3)
(define-constant SIGNIFICANCE_BREAKTHROUGH u4)

;; Discovery status
(define-constant STATUS_SUBMITTED u0)
(define-constant STATUS_UNDER_REVIEW u1)
(define-constant STATUS_VERIFIED u2)
(define-constant STATUS_REJECTED u3)

;; Data structures
(define-map discoveries
  { discovery-id: uint }
  {
    title: (string-ascii 200),
    description: (string-ascii 1000),
    researcher: principal,
    facility-id: uint,
    experiment-id: uint,
    significance-level: uint,
    status: uint,
    discovery-date: uint,
    verification-date: uint,
    data-hash: (buff 32),
    peer-reviews: uint
  }
)

(define-map discovery-reviews
  { discovery-id: uint, reviewer: principal }
  {
    rating: uint,
    comments: (string-ascii 500),
    review-date: uint
  }
)

(define-map researcher-achievements
  { researcher: principal }
  {
    total-discoveries: uint,
    verified-discoveries: uint,
    breakthrough-count: uint,
    reputation-score: uint
  }
)

(define-data-var next-discovery-id uint u1)

;; Submit a new discovery
(define-public (submit-discovery
  (title (string-ascii 200))
  (description (string-ascii 1000))
  (facility-id uint)
  (experiment-id uint)
  (significance-level uint)
  (data-hash (buff 32))
)
  (begin
    (asserts! (<= significance-level SIGNIFICANCE_BREAKTHROUGH) ERR_INVALID_SIGNIFICANCE)
    (let ((discovery-id (var-get next-discovery-id)))
      (map-set discoveries
        { discovery-id: discovery-id }
        {
          title: title,
          description: description,
          researcher: tx-sender,
          facility-id: facility-id,
          experiment-id: experiment-id,
          significance-level: significance-level,
          status: STATUS_SUBMITTED,
          discovery-date: block-height,
          verification-date: u0,
          data-hash: data-hash,
          peer-reviews: u0
        }
      )
      ;; Update researcher stats
      (update-researcher-discovery-count tx-sender)
      (var-set next-discovery-id (+ discovery-id u1))
      (ok discovery-id)
    )
  )
)

;; Submit peer review
(define-public (submit-review
  (discovery-id uint)
  (rating uint)
  (comments (string-ascii 500))
)
  (begin
    (asserts! (<= rating u10) ERR_INVALID_SIGNIFICANCE)
    (match (map-get? discoveries { discovery-id: discovery-id })
      discovery (begin
        (asserts! (not (is-eq (get researcher discovery) tx-sender)) ERR_UNAUTHORIZED)
        (map-set discovery-reviews
          { discovery-id: discovery-id, reviewer: tx-sender }
          {
            rating: rating,
            comments: comments,
            review-date: block-height
          }
        )
        ;; Increment review count
        (map-set discoveries
          { discovery-id: discovery-id }
          (merge discovery {
            peer-reviews: (+ (get peer-reviews discovery) u1)
          })
        )
        (ok true)
      )
      ERR_DISCOVERY_NOT_FOUND
    )
  )
)

;; Verify discovery (admin only)
(define-public (verify-discovery (discovery-id uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (match (map-get? discoveries { discovery-id: discovery-id })
      discovery (begin
        (asserts! (not (is-eq (get status discovery) STATUS_VERIFIED)) ERR_ALREADY_VERIFIED)
        (map-set discoveries
          { discovery-id: discovery-id }
          (merge discovery {
            status: STATUS_VERIFIED,
            verification-date: block-height
          })
        )
        ;; Update researcher achievements
        (update-researcher-verified-count (get researcher discovery) (get significance-level discovery))
        (ok true)
      )
      ERR_DISCOVERY_NOT_FOUND
    )
  )
)

;; Update discovery status
(define-public (update-discovery-status (discovery-id uint) (new-status uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-status STATUS_REJECTED) ERR_INVALID_SIGNIFICANCE)
    (match (map-get? discoveries { discovery-id: discovery-id })
      discovery (begin
        (map-set discoveries
          { discovery-id: discovery-id }
          (merge discovery { status: new-status })
        )
        (ok true)
      )
      ERR_DISCOVERY_NOT_FOUND
    )
  )
)

;; Helper functions
(define-private (update-researcher-discovery-count (researcher principal))
  (let ((current-achievements (default-to
    { total-discoveries: u0, verified-discoveries: u0, breakthrough-count: u0, reputation-score: u0 }
    (map-get? researcher-achievements { researcher: researcher }))))
    (map-set researcher-achievements
      { researcher: researcher }
      (merge current-achievements {
        total-discoveries: (+ (get total-discoveries current-achievements) u1)
      })
    )
  )
)

(define-private (update-researcher-verified-count (researcher principal) (significance uint))
  (let ((current-achievements (default-to
    { total-discoveries: u0, verified-discoveries: u0, breakthrough-count: u0, reputation-score: u0 }
    (map-get? researcher-achievements { researcher: researcher }))))
    (map-set researcher-achievements
      { researcher: researcher }
      (merge current-achievements {
        verified-discoveries: (+ (get verified-discoveries current-achievements) u1),
        breakthrough-count: (if (is-eq significance SIGNIFICANCE_BREAKTHROUGH)
          (+ (get breakthrough-count current-achievements) u1)
          (get breakthrough-count current-achievements)
        ),
        reputation-score: (+ (get reputation-score current-achievements) (* significance u10))
      })
    )
  )
)

;; Read-only functions
(define-read-only (get-discovery (discovery-id uint))
  (map-get? discoveries { discovery-id: discovery-id })
)

(define-read-only (get-review (discovery-id uint) (reviewer principal))
  (map-get? discovery-reviews { discovery-id: discovery-id, reviewer: reviewer })
)

(define-read-only (get-researcher-achievements (researcher principal))
  (map-get? researcher-achievements { researcher: researcher })
)

(define-read-only (is-discovery-verified (discovery-id uint))
  (match (map-get? discoveries { discovery-id: discovery-id })
    discovery (is-eq (get status discovery) STATUS_VERIFIED)
    false
  )
)

(define-read-only (get-researcher-reputation (researcher principal))
  (default-to u0
    (get reputation-score (map-get? researcher-achievements { researcher: researcher }))
  )
)
