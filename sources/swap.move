module defi::animeswap {
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    // use std::option;
    use sui::balance::{Self, Supply, Balance};
    // use sui::sui::SUI;
    use sui::transfer;
    use sui::math;
    use sui::tx_context::{Self, TxContext};
    use defi::animeswap_library::{quote, sqrt, get_amount_out, get_amount_in};
    // use std::debug;

    /// When contract error
    const ERR_INTERNAL_ERROR: u64 = 102;
    /// When user is not admin
    const ERR_FORBIDDEN: u64 = 103;
    /// When not enough amount for pool
    const ERR_INSUFFICIENT_AMOUNT: u64 = 104;
    /// When not enough liquidity amount
    const ERR_INSUFFICIENT_LIQUIDITY: u64 = 105;
    /// When not enough liquidity minted
    const ERR_INSUFFICIENT_LIQUIDITY_MINT: u64 = 106;
    /// When not enough liquidity burned
    const ERR_INSUFFICIENT_LIQUIDITY_BURN: u64 = 107;
    /// When not enough X amount
    const ERR_INSUFFICIENT_X_AMOUNT: u64 = 108;
    /// When not enough Y amount
    const ERR_INSUFFICIENT_Y_AMOUNT: u64 = 109;
    /// When not enough input amount
    const ERR_INSUFFICIENT_INPUT_AMOUNT: u64 = 110;
    /// When not enough output amount
    const ERR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 111;
    /// When contract K error
    const ERR_K_ERROR: u64 = 112;
    /// When already exists on account
    const ERR_PAIR_ALREADY_EXIST: u64 = 115;
    /// When not exists on account
    const ERR_PAIR_NOT_EXIST: u64 = 116;
    /// When error loan amount
    const ERR_LOAN_ERROR: u64 = 117;
    /// When contract is not reentrant
    const ERR_LOCK_ERROR: u64 = 118;
    /// When pair has wrong ordering
    const ERR_PAIR_ORDER_ERROR: u64 = 119;
    /// When contract is paused
    const ERR_PAUSABLE_ERROR: u64 = 120;

    const MINIMUM_LIQUIDITY: u64 = 1000;

    struct LPCoin<phantom X, phantom Y> has drop {}

    struct LiquidityPool<phantom X, phantom Y> has key {
        id: UID,
        coin_x_reserve: Balance<X>,
        coin_y_reserve: Balance<Y>,
        lp_coin_reserve: Balance<LPCoin<X, Y>>,
        lp_supply: Supply<LPCoin<X, Y>>,
    }

    /// Module initializer is empty
    /// To publish a new Pool one has to create a type which will mark LPCoins.
    fun init(_: &mut TxContext) {}

    /// get reserves size
    /// always return (X_reserve, Y_reserve)
    public fun get_reserves_size<X, Y>(pool: &LiquidityPool<X, Y>): (u64, u64) {
        (balance::value(&pool.coin_x_reserve), balance::value(&pool.coin_y_reserve))
    }

    /// get amounts out, 1 pair
    public fun get_amounts_out<X, Y>(
        pool: &LiquidityPool<X, Y>,
        amount_in: u64,
    ): u64 {
        let (reserve_in, reserve_out) = get_reserves_size<X, Y>(pool);
        let amount_out = get_amount_out(amount_in, reserve_in, reserve_out, 0);
        amount_out
    }

    /// get amounts in, 1 pair
    public fun get_amounts_in<X, Y>(
        pool: &LiquidityPool<X, Y>,
        amount_out: u64,
    ): u64 {
        let (reserve_in, reserve_out) = get_reserves_size<X, Y>(pool);
        let amount_in = get_amount_in(amount_out, reserve_in, reserve_out, 0);
        amount_in
    }

    /// return remaining coin.
    public fun return_remaining_coin<X>(
        coin: Coin<X>,
        ctx: &mut TxContext,
    ) {
        if (coin::value(&coin) == 0) {
            coin::destroy_zero(coin);
        } else {
            transfer::transfer(coin, tx_context::sender(ctx));
        };
    }

    /// Calculate optimal amounts of coins to add
    public fun calc_optimal_coin_values<X, Y>(
        pool: &LiquidityPool<X, Y>,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64
    ): (u64, u64) {
        let (reserve_x, reserve_y) = get_reserves_size(pool);
        if (reserve_x == 0 && reserve_y == 0) {
            (amount_x_desired, amount_y_desired)
        } else {
            let amount_y_optimal = quote(amount_x_desired, reserve_x, reserve_y);
            if (amount_y_optimal <= amount_y_desired) {
                assert!(amount_y_optimal >= amount_y_min, ERR_INSUFFICIENT_Y_AMOUNT);
                (amount_x_desired, amount_y_optimal)
            } else {
                let amount_x_optimal = quote(amount_y_desired, reserve_y, reserve_x);
                assert!(amount_x_optimal <= amount_x_desired, ERR_INTERNAL_ERROR);
                assert!(amount_x_optimal >= amount_x_min, ERR_INSUFFICIENT_X_AMOUNT);
                (amount_x_optimal, amount_y_desired)
            }
        }
    }

    public entry fun create_pair_entry<X, Y>(
        ctx: &mut TxContext,
    ) {
        transfer::share_object(LiquidityPool<X, Y> {
            id: object::new(ctx),
            coin_x_reserve: balance::zero<X>(),
            coin_y_reserve: balance::zero<Y>(),
            lp_coin_reserve: balance::zero(),
            lp_supply: balance::create_supply(LPCoin<X, Y> {}),
        });
    }

    public entry fun add_liquidity_entry<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coin_x_origin: Coin<X>,
        coin_y_origin: Coin<Y>,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64,
        ctx: &mut TxContext,
    ) {
        let lp_coins = add_liquidity<X, Y>(
            pool,
            coin_x_origin,
            coin_y_origin,
            amount_x_desired,
            amount_y_desired,
            amount_x_min,
            amount_y_min,
            ctx,
        );
        transfer::transfer(lp_coins, tx_context::sender(ctx));
    }

    public entry fun remove_liquidity_entry<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        liquidity: Coin<LPCoin<X, Y>>,
        liquidity_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64,
        ctx: &mut TxContext,
    ) {
        let (coin_x, coin_y) = remove_liquidity<X, Y>(
            pool,
            liquidity,
            liquidity_desired,
            amount_x_min,
            amount_y_min,
            ctx,
        );
        transfer::transfer(coin_x, tx_context::sender(ctx));
        transfer::transfer(coin_y, tx_context::sender(ctx));
    }

    public fun add_liquidity<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coin_x_origin: Coin<X>,
        coin_y_origin: Coin<Y>,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64,
        ctx: &mut TxContext,
    ): Coin<LPCoin<X, Y>> {
        let amt_x = coin::value(&coin_x_origin);
        let amt_y = coin::value(&coin_y_origin);

        assert!(amt_x >= amount_x_desired
            && amount_x_desired >= amount_x_min
            && amount_x_min > 0,
            ERR_INSUFFICIENT_X_AMOUNT);
        assert!(amt_y >= amount_y_desired
            && amount_y_desired >= amount_y_min
            && amount_y_min > 0,
            ERR_INSUFFICIENT_Y_AMOUNT);

        let (amount_x, amount_y) =
            calc_optimal_coin_values<X, Y>(pool, amount_x_desired, amount_y_desired, amount_x_min, amount_y_min);
        let coin_x = coin::split(&mut coin_x_origin, amount_x, ctx);
        let coin_y = coin::split(&mut coin_y_origin, amount_y, ctx);
        let lp_balance = mint<X, Y>(pool, coin::into_balance<X>(coin_x), coin::into_balance<Y>(coin_y));
        let lp_coins = coin::from_balance<LPCoin<X, Y>>(lp_balance, ctx);
        return_remaining_coin(coin_x_origin, ctx);
        return_remaining_coin(coin_y_origin, ctx);
        lp_coins
    }

    public fun remove_liquidity<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        liquidity: Coin<LPCoin<X, Y>>,
        liquidity_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64,
        ctx: &mut TxContext,
    ): (Coin<X>, Coin<Y>) {
        let amt_lp = coin::value(&liquidity);
        assert!(amt_lp >= liquidity_desired, ERR_INSUFFICIENT_INPUT_AMOUNT);
        let coin_lp = coin::split(&mut liquidity, liquidity_desired, ctx);
        let (x_balance, y_balance) = burn<X, Y>(pool, coin::into_balance(coin_lp));
        let x_out = coin::from_balance(x_balance, ctx);
        let y_out = coin::from_balance(y_balance, ctx);
        assert!(coin::value(&x_out) >= amount_x_min, ERR_INSUFFICIENT_X_AMOUNT);
        assert!(coin::value(&y_out) >= amount_y_min, ERR_INSUFFICIENT_Y_AMOUNT);
        return_remaining_coin(liquidity, ctx);
        (x_out, y_out)
    }

    /// entry, swap from X to Y
    public entry fun swap_exact_coins_for_coins_1<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coins_in_origin: Coin<X>,
        amount_in: u64,
        amount_out_min: u64,
        ctx: &mut TxContext,
    ) {
        let coins_in = coin::split(&mut coins_in_origin, amount_in, ctx);
        let coins_out = swap_coins_for_coins_1<X, Y>(pool, coins_in, ctx);
        assert!(coin::value(&coins_out) >= amount_out_min, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
        return_remaining_coin(coins_in_origin, ctx);
        transfer::transfer(coins_out, tx_context::sender(ctx));
    }

    /// swap from Coin X to Coin Y
    public fun swap_coins_for_coins_1<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coins_in: Coin<X>,
        ctx: &mut TxContext,
    ): Coin<Y> {
        let balance_out = swap_balance_for_balance_1<X, Y>(pool, coin::into_balance<X>(coins_in));
        let coins_out = coin::from_balance<Y>(balance_out, ctx);
        coins_out
    }

    /// swap from Balance X to Balance Y
    public fun swap_balance_for_balance_1<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coins_in: Balance<X>,
    ): Balance<Y> {
        let amount_in = balance::value(&coins_in);
        let (reserve_in, reserve_out) = get_reserves_size<X, Y>(pool);
        let amount_out = get_amount_out(amount_in, reserve_in, reserve_out, 0);
        let (zero, coins_out) = swap<X, Y>(pool, coins_in, 0, balance::zero(), amount_out);
        balance::destroy_zero<X>(zero);
        coins_out
    }

    /// entry, swap from Y to X
    public entry fun swap_exact_coins_for_coins_2<Y, X>(
        pool: &mut LiquidityPool<X, Y>,
        coins_in_origin: Coin<Y>,
        amount_in: u64,
        amount_out_min: u64,
        ctx: &mut TxContext,
    ) {
        let coins_in = coin::split(&mut coins_in_origin, amount_in, ctx);
        let coins_out = swap_coins_for_coins_2<Y, X>(pool, coins_in, ctx);
        assert!(coin::value(&coins_out) >= amount_out_min, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
        return_remaining_coin(coins_in_origin, ctx);
        transfer::transfer(coins_out, tx_context::sender(ctx));
    }

    /// swap from Coin Y to Coin X
    public fun swap_coins_for_coins_2<Y, X>(
        pool: &mut LiquidityPool<X, Y>,
        coins_in: Coin<Y>,
        ctx: &mut TxContext,
    ): Coin<X> {
        let balance_out = swap_balance_for_balance_2<Y, X>(pool, coin::into_balance<Y>(coins_in));
        let coins_out = coin::from_balance<X>(balance_out, ctx);
        coins_out
    }

    /// swap from Balance Y to Balance X
    public fun swap_balance_for_balance_2<Y, X>(
        pool: &mut LiquidityPool<X, Y>,
        coins_in: Balance<Y>,
    ): Balance<X> {
        let amount_in = balance::value(&coins_in);
        let (reserve_out, reserve_in) = get_reserves_size<X, Y>(pool);
        let amount_out = get_amount_out(amount_in, reserve_in, reserve_out, 0);
        let (coins_out, zero) = swap<X, Y>(pool, balance::zero(), amount_out, coins_in, 0);
        balance::destroy_zero<Y>(zero);
        coins_out
    }

    /// Swap coins
    public fun swap<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coins_x_in: Balance<X>,
        amount_x_out: u64,
        coins_y_in: Balance<Y>,
        amount_y_out: u64,
    ): (Balance<X>, Balance<Y>) {
        let amount_x_in = balance::value(&coins_x_in);
        let amount_y_in = balance::value(&coins_y_in);
        assert!(amount_x_in > 0 || amount_y_in > 0, ERR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(amount_x_out > 0 || amount_y_out > 0, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
        balance::join<X>(&mut pool.coin_x_reserve, coins_x_in);
        balance::join<Y>(&mut pool.coin_y_reserve, coins_y_in);
        let coins_x_out = balance::split(&mut pool.coin_x_reserve, amount_x_out);
        let coins_y_out = balance::split(&mut pool.coin_y_reserve, amount_y_out);
        // TODO assert_k_increase
        (coins_x_out, coins_y_out)
    }

    public fun mint<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coin_x: Balance<X>,
        coin_y: Balance<Y>,
    ): Balance<LPCoin<X, Y>> {
        let amount_x = balance::value(&coin_x);
        let amount_y = balance::value(&coin_y);
        let (reserve_x, reserve_y) = get_reserves_size(pool);
        let total_supply = balance::supply_value<LPCoin<X, Y>>(&pool.lp_supply);
        balance::join<X>(&mut pool.coin_x_reserve, coin_x);
        balance::join<Y>(&mut pool.coin_y_reserve, coin_y);
        let liquidity;
        if (total_supply == 0) {
            liquidity = sqrt(amount_x, amount_y) - MINIMUM_LIQUIDITY;
            let balance_reserve = balance::increase_supply(&mut pool.lp_supply, MINIMUM_LIQUIDITY);
            balance::join(&mut pool.lp_coin_reserve, balance_reserve);
        } else {
            let amount_1 = ((amount_x as u128) * (total_supply as u128) / (reserve_x as u128) as u64);
            let amount_2 = ((amount_y as u128) * (total_supply as u128) / (reserve_y as u128) as u64);
            liquidity = math::min(amount_1, amount_2);
        };
        assert!(liquidity > 0, ERR_INSUFFICIENT_LIQUIDITY_MINT);
        let coins = balance::increase_supply(&mut pool.lp_supply, liquidity);
        coins
    }

    public fun burn<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        liquidity: Balance<LPCoin<X, Y>>,
    ): (Balance<X>, Balance<Y>) {
        let liquidity_amount = balance::value(&liquidity);
        let (reserve_x, reserve_y) = get_reserves_size(pool);
        let total_supply = balance::supply_value<LPCoin<X, Y>>(&pool.lp_supply);
        let amount_x = ((liquidity_amount as u128) * (reserve_x as u128) / (total_supply as u128) as u64);
        let amount_y = ((liquidity_amount as u128) * (reserve_y as u128) / (total_supply as u128) as u64);
        let x_coin_to_return = balance::split(&mut pool.coin_x_reserve, amount_x);
        let y_coin_to_return = balance::split(&mut pool.coin_y_reserve, amount_y);
        balance::decrease_supply(&mut pool.lp_supply, liquidity);
        (x_coin_to_return, y_coin_to_return)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}

#[test_only]
module defi::animeswap_tests {
    use sui::coin::{mint_for_testing as mint, destroy_for_testing as burn};
    // use sui::balance::{Self};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use defi::animeswap::{Self, LPCoin, LiquidityPool};
    // use std::debug;

    const TEST_ERROR: u64 = 10000;

    /// Gonna be our test token.
    struct TestCoin1 has drop {}
    struct TestCoin2 has drop {}

    #[test]
    fun test_add_remove_lp_basic() {
        let scenario = scenario();
        let (owner, one, _) = people();
        next_tx(&mut scenario, owner);
        {
            let test = &mut scenario;
            animeswap::init_for_testing(ctx(test));
            animeswap::create_pair_entry<TestCoin1, TestCoin2>(ctx(test));
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let pool = test::take_shared<LiquidityPool<TestCoin1, TestCoin2>>(test);
            let pool_mut = &mut pool;
            let lp_coins = animeswap::add_liquidity<TestCoin1, TestCoin2>(
                pool_mut,
                mint<TestCoin1>(10000, ctx(test)),
                mint<TestCoin2>(20000, ctx(test)),
                10000,
                10000,
                1,
                1,
                ctx(test),
            );
            assert!(burn(lp_coins) == 9000, TEST_ERROR);
            test::return_shared(pool);
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let pool = test::take_shared<LiquidityPool<TestCoin1, TestCoin2>>(test);
            let pool_mut = &mut pool;
            let lp_coins = animeswap::add_liquidity<TestCoin1, TestCoin2>(
                pool_mut,
                mint<TestCoin1>(10000, ctx(test)),
                mint<TestCoin2>(20000, ctx(test)),
                10000,
                10000,
                1,
                1,
                ctx(test),
            );

            assert!(burn(lp_coins) == 10000, TEST_ERROR);
            test::return_shared(pool);
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let pool = test::take_shared<LiquidityPool<TestCoin1, TestCoin2>>(test);
            let pool_mut = &mut pool;
            let (coin_x, coin_y) = animeswap::remove_liquidity<TestCoin1, TestCoin2>(
                pool_mut,
                mint<LPCoin<TestCoin1, TestCoin2>>(1000, ctx(test)),
                500,
                1,
                1,
                ctx(test),
            );

            assert!(burn(coin_x) == 500, TEST_ERROR);
            assert!(burn(coin_y) == 500, TEST_ERROR);
            test::return_shared(pool);
        };
        test::end(scenario);
    }

    #[test]
    fun test_swap_lp_basic() {
        let scenario = scenario();
        let (owner, one, _) = people();
        next_tx(&mut scenario, owner);
        {
            let test = &mut scenario;
            animeswap::init_for_testing(ctx(test));
            animeswap::create_pair_entry<TestCoin1, TestCoin2>(ctx(test));
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let pool = test::take_shared<LiquidityPool<TestCoin1, TestCoin2>>(test);
            let pool_mut = &mut pool;
            let lp_coins = animeswap::add_liquidity<TestCoin1, TestCoin2>(
                pool_mut,
                mint<TestCoin1>(10000, ctx(test)),
                mint<TestCoin2>(20000, ctx(test)),
                10000,
                10000,
                1,
                1,
                ctx(test),
            );
            assert!(burn(lp_coins) == 9000, TEST_ERROR);
            test::return_shared(pool);
        };
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let pool = test::take_shared<LiquidityPool<TestCoin1, TestCoin2>>(test);
            let pool_mut = &mut pool;
            let coins_out = animeswap::swap_coins_for_coins_1<TestCoin1, TestCoin2>(
                pool_mut,
                mint<TestCoin1>(1000, ctx(test)),
                ctx(test),
            );
            assert!(burn(coins_out) == 909, TEST_ERROR);
            test::return_shared(pool);
        };
        test::end(scenario);
    }

    // utilities
    fun scenario(): Scenario { test::begin(@0x1) }
    fun people(): (address, address, address) { (@0xBEEF, @0x1111, @0x2222) }
}