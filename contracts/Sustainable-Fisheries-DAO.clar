
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
(define-constant err-not-listed (err u109))
(define-constant err-invalid-price (err u110))
(define-constant err-cannot-buy-own (err u111))
(define-constant err-not-staked (err u112))
(define-constant err-insufficient-stake (err u113))
(define-constant err-cannot-delegate-self (err u114))

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

(define-map quota-listings
  uint
  {
    quota-id: uint,
    seller: principal,
    price: uint,
    active: bool
  })

(define-map stakes
  principal
  {
    staked-amount: uint,
    delegated-to: (optional principal)
  })

(define-map delegation-received
  principal
  uint)

(define-data-var report-counter uint u0)
(define-data-var marketplace-commission uint u5)
(define-data-var listing-counter uint u0)
(define-data-var total-staked uint u0)

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

(define-public (list-quota-for-sale (quota-id uint) (price uint))
  (let
    ((quota-data (unwrap! (map-get? quotas quota-id) err-not-found))
     (fisher-data (unwrap! (map-get? fishers tx-sender) err-not-found))
     (listing-id (+ (var-get listing-counter) u1)))
    (asserts! (get registered fisher-data) err-not-authorized)
    (asserts! (get active fisher-data) err-frozen)
    (asserts! (not (get frozen quota-data)) err-frozen)
    (asserts! (is-eq (get fisher quota-data) tx-sender) err-not-authorized)
    (asserts! (> price u0) err-invalid-price)
    (map-set quota-listings listing-id
      {
        quota-id: quota-id,
        seller: tx-sender,
        price: price,
        active: true
      })
    (var-set listing-counter listing-id)
    (ok listing-id)))

(define-public (buy-quota-from-marketplace (listing-id uint))
  (let
    ((listing-data (unwrap! (map-get? quota-listings listing-id) err-not-listed))
     (quota-data (unwrap! (map-get? quotas (get quota-id listing-data)) err-not-found))
     (buyer-data (unwrap! (map-get? fishers tx-sender) err-not-found))
     (seller-data (unwrap! (map-get? fishers (get seller listing-data)) err-not-found))
     (price (get price listing-data))
     (commission (/ (* price (var-get marketplace-commission)) u100))
     (seller-payout (- price commission))
     (target-quota-id (get quota-id listing-data)))
    (asserts! (get active listing-data) err-not-listed)
    (asserts! (get registered buyer-data) err-not-authorized)
    (asserts! (get active buyer-data) err-frozen)
    (asserts! (not (is-eq tx-sender (get seller listing-data))) err-cannot-buy-own)
    (asserts! (>= (ft-get-balance fisheries-token tx-sender) price) err-insufficient-balance)
    (try! (ft-transfer? fisheries-token seller-payout tx-sender (get seller listing-data)))
    (try! (ft-transfer? fisheries-token commission tx-sender contract-owner))
    (try! (nft-transfer? fishing-quota target-quota-id (get seller listing-data) tx-sender))
    (map-set quotas target-quota-id
      (merge quota-data { fisher: tx-sender }))
    (var-set filter-quota-id target-quota-id)
    (let
      ((seller-quotas (default-to (list) (map-get? fisher-quotas (get seller listing-data))))
       (buyer-quotas (default-to (list) (map-get? fisher-quotas tx-sender)))
       (filtered-seller-quotas (filter is-not-target-quota seller-quotas)))
      (map-set fisher-quotas (get seller listing-data) filtered-seller-quotas)
      (map-set fisher-quotas tx-sender (unwrap! (as-max-len? (append buyer-quotas target-quota-id) u10) err-invalid-amount)))
    (map-set quota-listings listing-id
      (merge listing-data { active: false }))
    (var-set treasury-balance (+ (var-get treasury-balance) commission))
    (ok true)))

(define-public (cancel-quota-listing (listing-id uint))
  (let
    ((listing-data (unwrap! (map-get? quota-listings listing-id) err-not-listed)))
    (asserts! (get active listing-data) err-not-listed)
    (asserts! (is-eq tx-sender (get seller listing-data)) err-not-authorized)
    (map-set quota-listings listing-id
      (merge listing-data { active: false }))
    (ok true)))

(define-public (update-marketplace-commission (new-commission uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-commission u20) err-invalid-amount)
    (var-set marketplace-commission new-commission)
    (ok true)))

(define-read-only (get-quota-listing (listing-id uint))
  (map-get? quota-listings listing-id))

(define-read-only (get-marketplace-commission)
  (var-get marketplace-commission))

(define-data-var filter-quota-id uint u0)

(define-private (is-not-target-quota (id uint))
  (not (is-eq id (var-get filter-quota-id))))

(define-public (stake-tokens (amount uint))
  (let
    ((fisher-data (unwrap! (map-get? fishers tx-sender) err-not-found))
     (current-stake (default-to { staked-amount: u0, delegated-to: none } (map-get? stakes tx-sender))))
    (asserts! (get registered fisher-data) err-not-authorized)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= (ft-get-balance fisheries-token tx-sender) amount) err-insufficient-balance)
    (try! (ft-burn? fisheries-token amount tx-sender))
    (map-set stakes tx-sender
      {
        staked-amount: (+ (get staked-amount current-stake) amount),
        delegated-to: (get delegated-to current-stake)
      })
    (var-set total-staked (+ (var-get total-staked) amount))
    (ok true)))

(define-public (unstake-tokens (amount uint))
  (let
    ((current-stake (unwrap! (map-get? stakes tx-sender) err-not-staked))
     (staked-amt (get staked-amount current-stake)))
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= staked-amt amount) err-insufficient-stake)
    (if (is-some (get delegated-to current-stake))
      (let
        ((delegate (unwrap-panic (get delegated-to current-stake)))
         (current-delegation (default-to u0 (map-get? delegation-received delegate))))
        (map-set delegation-received delegate (if (>= current-delegation amount) (- current-delegation amount) u0)))
      true)
    (try! (ft-mint? fisheries-token amount tx-sender))
    (map-set stakes tx-sender
      {
        staked-amount: (- staked-amt amount),
        delegated-to: (get delegated-to current-stake)
      })
    (var-set total-staked (- (var-get total-staked) amount))
    (ok true)))

(define-public (delegate-stake (delegate principal))
  (let
    ((current-stake (unwrap! (map-get? stakes tx-sender) err-not-staked))
     (delegate-data (unwrap! (map-get? fishers delegate) err-not-found))
     (staked-amt (get staked-amount current-stake)))
    (asserts! (> staked-amt u0) err-insufficient-stake)
    (asserts! (get registered delegate-data) err-not-found)
    (asserts! (get active delegate-data) err-frozen)
    (asserts! (not (is-eq tx-sender delegate)) err-cannot-delegate-self)
    (if (is-some (get delegated-to current-stake))
      (let
        ((old-delegate (unwrap-panic (get delegated-to current-stake)))
         (old-delegation (default-to u0 (map-get? delegation-received old-delegate))))
        (map-set delegation-received old-delegate (if (>= old-delegation staked-amt) (- old-delegation staked-amt) u0)))
      true)
    (map-set stakes tx-sender
      {
        staked-amount: staked-amt,
        delegated-to: (some delegate)
      })
    (let
      ((current-delegation (default-to u0 (map-get? delegation-received delegate))))
      (map-set delegation-received delegate (+ current-delegation staked-amt)))
    (ok true)))

(define-public (undelegate-stake)
  (let
    ((current-stake (unwrap! (map-get? stakes tx-sender) err-not-staked))
     (staked-amt (get staked-amount current-stake)))
    (asserts! (is-some (get delegated-to current-stake)) err-not-found)
    (let
      ((delegate (unwrap-panic (get delegated-to current-stake)))
       (current-delegation (default-to u0 (map-get? delegation-received delegate))))
      (map-set delegation-received delegate (if (>= current-delegation staked-amt) (- current-delegation staked-amt) u0)))
    (map-set stakes tx-sender
      {
        staked-amount: staked-amt,
        delegated-to: none
      })
    (ok true)))

(define-read-only (get-stake-info (staker principal))
  (map-get? stakes staker))

(define-read-only (get-voting-power (address principal))
  (let
    ((own-stake (default-to { staked-amount: u0, delegated-to: none } (map-get? stakes address)))
     (delegated (default-to u0 (map-get? delegation-received address))))
    (ok (+ (get staked-amount own-stake) delegated))))

(define-read-only (get-total-staked)
  (var-get total-staked))
