;; Data Sharing Protocol Contract
;; Facilitates dark matter research data collaboration

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_DATA_NOT_FOUND (err u301))
(define-constant ERR_ACCESS_DENIED (err u302))
(define-constant ERR_INVALID_PERMISSION (err u303))

;; Permission levels
(define-constant PERMISSION_READ u1)
(define-constant PERMISSION_WRITE u2)
(define-constant PERMISSION_ADMIN u3)

;; Data structures
(define-map research-data
  { data-id: uint }
  {
    title: (string-ascii 200),
    description: (string-ascii 500),
    data-hash: (buff 32),
    owner: principal,
    experiment-id: uint,
    classification-level: uint,
    created-date: uint,
    last-modified: uint
  }
)

(define-map data-permissions
  { data-id: uint, user: principal }
  { permission-level: uint, granted-date: uint }
)

(define-map data-access-log
  { data-id: uint, user: principal, access-time: uint }
  { action: (string-ascii 50) }
)

(define-data-var next-data-id uint u1)

;; Upload research data
(define-public (upload-data
  (title (string-ascii 200))
  (description (string-ascii 500))
  (data-hash (buff 32))
  (experiment-id uint)
  (classification-level uint)
)
  (let ((data-id (var-get next-data-id)))
    (map-set research-data
      { data-id: data-id }
      {
        title: title,
        description: description,
        data-hash: data-hash,
        owner: tx-sender,
        experiment-id: experiment-id,
        classification-level: classification-level,
        created-date: block-height,
        last-modified: block-height
      }
    )
    ;; Grant admin permission to owner
    (map-set data-permissions
      { data-id: data-id, user: tx-sender }
      { permission-level: PERMISSION_ADMIN, granted-date: block-height }
    )
    (var-set next-data-id (+ data-id u1))
    (ok data-id)
  )
)

;; Grant data access permission
(define-public (grant-permission (data-id uint) (user principal) (permission-level uint))
  (begin
    (asserts! (<= permission-level PERMISSION_ADMIN) ERR_INVALID_PERMISSION)
    (asserts! (has-admin-permission data-id tx-sender) ERR_UNAUTHORIZED)
    (map-set data-permissions
      { data-id: data-id, user: user }
      { permission-level: permission-level, granted-date: block-height }
    )
    (ok true)
  )
)

;; Revoke data access permission
(define-public (revoke-permission (data-id uint) (user principal))
  (begin
    (asserts! (has-admin-permission data-id tx-sender) ERR_UNAUTHORIZED)
    (map-delete data-permissions { data-id: data-id, user: user })
    (ok true)
  )
)

;; Access data (logs the access)
(define-public (access-data (data-id uint))
  (begin
    (asserts! (has-read-permission data-id tx-sender) ERR_ACCESS_DENIED)
    (map-set data-access-log
      { data-id: data-id, user: tx-sender, access-time: block-height }
      { action: "read" }
    )
    (match (map-get? research-data { data-id: data-id })
      data (ok data)
      ERR_DATA_NOT_FOUND
    )
  )
)

;; Update data (requires write permission)
(define-public (update-data (data-id uint) (new-data-hash (buff 32)) (description (string-ascii 500)))
  (begin
    (asserts! (has-write-permission data-id tx-sender) ERR_ACCESS_DENIED)
    (match (map-get? research-data { data-id: data-id })
      data (begin
        (map-set research-data
          { data-id: data-id }
          (merge data {
            data-hash: new-data-hash,
            description: description,
            last-modified: block-height
          })
        )
        (map-set data-access-log
          { data-id: data-id, user: tx-sender, access-time: block-height }
          { action: "write" }
        )
        (ok true)
      )
      ERR_DATA_NOT_FOUND
    )
  )
)

;; Helper functions
(define-private (has-read-permission (data-id uint) (user principal))
  (match (map-get? data-permissions { data-id: data-id, user: user })
    permission (>= (get permission-level permission) PERMISSION_READ)
    false
  )
)

(define-private (has-write-permission (data-id uint) (user principal))
  (match (map-get? data-permissions { data-id: data-id, user: user })
    permission (>= (get permission-level permission) PERMISSION_WRITE)
    false
  )
)

(define-private (has-admin-permission (data-id uint) (user principal))
  (match (map-get? data-permissions { data-id: data-id, user: user })
    permission (>= (get permission-level permission) PERMISSION_ADMIN)
    false
  )
)

;; Read-only functions
(define-read-only (get-data-info (data-id uint))
  (map-get? research-data { data-id: data-id })
)

(define-read-only (get-user-permission (data-id uint) (user principal))
  (map-get? data-permissions { data-id: data-id, user: user })
)

(define-read-only (can-access-data (data-id uint) (user principal))
  (has-read-permission data-id user)
)
