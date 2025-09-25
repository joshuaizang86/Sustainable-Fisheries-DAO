
(define-non-fungible-token fishing-quota uint)

(define-fungible-token fisheries-token)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-not-found (err u103))
(define-constant err-quota-exceeded (err u104))
(define-constant err-frozen (err u105))
(define-constant err-invalid-amount (err u106))
(define-constant err-insufficient-balance (err u107))
(define-constant err-oracle-only (err u108))

(define-data-var quota-counter uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var reporting-reward uint u100)
(define-data-var penalty-amount uint u500)

(define-map fishers
  principal
  {
    registered: bool,
    active: bool,
    reputation: uint,
    total-catch: uint,
    violations: uint
  })

(define-map quotas
  uint
  {
    fisher: principal,
    species: (string-ascii 32),
    max-catch: uint,
    current-catch: uint,
    season-start: uint,
    season-end: uint,
    frozen: bool
  })

(define-map fisher-quotas
  principal
  (list 10 uint))

(define-map oracles
  principal
  bool)

(define-map catch-reports
  uint
  {
    fisher: principal,
    quota-id: uint,
    amount: uint,
    timestamp: uint,
    verified: bool,
    reporter: principal
  })

(define-data-var report-counter uint u0)

(define-public (register-fisher)
  (let
    ((fisher-data (default-to
      { registered: false, active: false, reputation: u0, total-catch: u0, violations: u0 }
      (map-get? fishers tx-sender))))
    (asserts! (not (get registered fisher-data)) err-already-exists)
    (map-set fishers tx-sender
      {
        registered: true,
        active: true,
        reputation: u100,
        total-catch: u0,
        violations: u0
      })
    (try! (ft-mint? fisheries-token u1000 tx-sender))
    (ok true)))

(define-public (issue-quota (fisher principal) (species (string-ascii 32)) (max-catch uint) (season-start uint) (season-end uint))
  (let
    ((quota-id (+ (var-get quota-counter) u1))
     (fisher-data (unwrap! (map-get? fishers fisher) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (get registered fisher-data) err-not-found)
    (asserts! (get active fisher-data) err-frozen)
    (asserts! (> max-catch u0) err-invalid-amount)
    (try! (nft-mint? fishing-quota quota-id fisher))
    (map-set quotas quota-id
      {
        fisher: fisher,
        species: species,
        max-catch: max-catch,
        current-catch: u0,
        season-start: season-start,
        season-end: season-end,
        frozen: false
      })
    (let
      ((current-quotas (default-to (list) (map-get? fisher-quotas fisher))))
      (map-set fisher-quotas fisher (unwrap! (as-max-len? (append current-quotas quota-id) u10) err-invalid-amount)))
    (var-set quota-counter quota-id)
    (ok quota-id)))

(define-public (report-catch (quota-id uint) (amount uint))
  (let
    ((quota-data (unwrap! (map-get? quotas quota-id) err-not-found))
     (fisher-data (unwrap! (map-get? fishers tx-sender) err-not-found))
     (report-id (+ (var-get report-counter) u1)))
    (asserts! (get registered fisher-data) err-not-authorized)
    (asserts! (get active fisher-data) err-frozen)
    (asserts! (not (get frozen quota-data)) err-frozen)
    (asserts! (is-eq (get fisher quota-data) tx-sender) err-not-authorized)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (<= (+ (get current-catch quota-data) amount) (get max-catch quota-data)) err-quota-exceeded)
    (map-set catch-reports report-id
      {
        fisher: tx-sender,
        quota-id: quota-id,
        amount: amount,
        timestamp: u0,
        verified: false,
        reporter: tx-sender
      })
    (var-set report-counter report-id)
    (ok report-id)))

(define-public (verify-catch-report (report-id uint))
  (let
    ((report-data (unwrap! (map-get? catch-reports report-id) err-not-found))
     (quota-data (unwrap! (map-get? quotas (get quota-id report-data)) err-not-found))
     (fisher-data (unwrap! (map-get? fishers (get fisher report-data)) err-not-found)))
    (asserts! (default-to false (map-get? oracles tx-sender)) err-oracle-only)
    (asserts! (not (get verified report-data)) err-already-exists)
    (let
      ((new-catch-total (+ (get current-catch quota-data) (get amount report-data))))
      (map-set quotas (get quota-id report-data)
        (merge quota-data { current-catch: new-catch-total }))
      (map-set fishers (get fisher report-data)
        (merge fisher-data { total-catch: (+ (get total-catch fisher-data) (get amount report-data)) }))
      (map-set catch-reports report-id
        (merge report-data { verified: true }))
      (try! (ft-mint? fisheries-token (var-get reporting-reward) (get fisher report-data)))
      (if (>= new-catch-total (get max-catch quota-data))
        (map-set quotas (get quota-id report-data)
          (merge quota-data { frozen: true }))
        true)
      (ok true))))

(define-public (add-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set oracles oracle true)
    (ok true)))

(define-public (remove-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-delete oracles oracle)
    (ok true)))

(define-public (penalize-fisher (fisher principal) (violation-type (string-ascii 32)))
  (let
    ((fisher-data (unwrap! (map-get? fishers fisher) err-not-found)))
    (asserts! (default-to false (map-get? oracles tx-sender)) err-oracle-only)
    (asserts! (get registered fisher-data) err-not-found)
    (let
      ((new-violations (+ (get violations fisher-data) u1))
       (penalty (var-get penalty-amount)))
      (map-set fishers fisher
        (merge fisher-data 
          { 
            violations: new-violations,
            reputation: (if (> (get reputation fisher-data) penalty) (- (get reputation fisher-data) penalty) u0),
            active: (< new-violations u3)
          }))
      (if (>= (ft-get-balance fisheries-token fisher) penalty)
        (try! (ft-burn? fisheries-token penalty fisher))
        true)
      (var-set treasury-balance (+ (var-get treasury-balance) penalty))
      (ok true))))

(define-public (reward-sustainable-practice (fisher principal) (reward-amount uint))
  (let
    ((fisher-data (unwrap! (map-get? fishers fisher) err-not-found)))
    (asserts! (default-to false (map-get? oracles tx-sender)) err-oracle-only)
    (asserts! (get registered fisher-data) err-not-found)
    (asserts! (get active fisher-data) err-frozen)
    (asserts! (<= reward-amount (var-get treasury-balance)) err-insufficient-balance)
    (try! (ft-mint? fisheries-token reward-amount fisher))
    (map-set fishers fisher
      (merge fisher-data { reputation: (+ (get reputation fisher-data) (/ reward-amount u10)) }))
    (var-set treasury-balance (- (var-get treasury-balance) reward-amount))
    (ok true)))

(define-public (renew-quota (quota-id uint) (new-season-start uint) (new-season-end uint))
  (let
    ((quota-data (unwrap! (map-get? quotas quota-id) err-not-found))
     (fisher-data (unwrap! (map-get? fishers (get fisher quota-data)) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (get registered fisher-data) err-not-found)
    (asserts! (get active fisher-data) err-frozen)
    (map-set quotas quota-id
      (merge quota-data
        {
          current-catch: u0,
          season-start: new-season-start,
          season-end: new-season-end,
          frozen: false
        }))
    (ok true)))

(define-public (update-settings (new-reporting-reward uint) (new-penalty-amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set reporting-reward new-reporting-reward)
    (var-set penalty-amount new-penalty-amount)
    (ok true)))

(define-read-only (get-fisher-info (fisher principal))
  (map-get? fishers fisher))

(define-read-only (get-quota-info (quota-id uint))
  (map-get? quotas quota-id))

(define-read-only (get-fisher-quotas (fisher principal))
  (map-get? fisher-quotas fisher))

(define-read-only (get-catch-report (report-id uint))
  (map-get? catch-reports report-id))

(define-read-only (is-oracle (address principal))
  (default-to false (map-get? oracles address)))

(define-read-only (get-treasury-balance)
  (var-get treasury-balance))

(define-read-only (get-quota-utilization (quota-id uint))
  (match (map-get? quotas quota-id)
    quota-data (ok (/ (* (get current-catch quota-data) u100) (get max-catch quota-data)))
    err-not-found))

(define-read-only (get-contract-stats)
  {
    total-quotas: (var-get quota-counter),
    total-reports: (var-get report-counter),
    treasury-balance: (var-get treasury-balance),
    reporting-reward: (var-get reporting-reward),
    penalty-amount: (var-get penalty-amount)
  })
