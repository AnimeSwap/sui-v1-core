# AnimeSwap

**AnimeSwap** is AMM protocol for [Aptos](https://www.aptos.com/) and [SUI](https://sui.io/) blockchain. 

* [Contracts documents](https://docs.animeswap.org/docs/contracts)
* [SDK](https://github.com/AnimeSwap/sui-v1-sdk)

The current repository contains: 

* swap_library
* swap
* uq64x64

## Add as dependency

Update your `Move.toml` with

```toml
[dependencies.animeSwap]
git = 'https://github.com/AnimeSwap/sui-v1-core.git'
rev = '0.0.2'
```

-----

Swap example:
```move
use animeswap::animeswap_library;
use animeswap::animeswap::{Self, LiquidityPools};
...
fun swap_pair<X, Y> (
    lps: &mut LiquidityPools,
    clock: &Clock,
    x_in: Coin<X>,
    ctx: &mut TxContext,
): Coin<Y> {
    if (animeswap_library::compare<X, Y>()) {
        let (zero, coins_out) = animeswap::swap_coins_for_coins<X, Y>(
            lps,
            clock,
            x_in,
            coin::zero(ctx),
            ctx,
        );
        coin::destroy_zero(zero);
        coins_out
    } else {
        let (coins_out, zero) = animeswap::swap_coins_for_coins<Y, X>(
            lps,
            clock,
            coin::zero(ctx),
            x_in,
            ctx,
        );
        coin::destroy_zero(zero);
        coins_out
    }
}
```

-----

Flash swap example:
```move
use animeswap::animeswap_library;
use animeswap::animeswap::{Self, LiquidityPools};
...
fun swap_pair_with_flash_swap<X, Y>(
    lps: &mut LiquidityPools,
    clock: &Clock,
    x_in: Coin<X>,
    amount: u64,
    ctx: &mut TxContext,
) {
    if (animeswap_library::compare<X, Y>()) {
        // flash loan Y
        let (balance_in_zero, balance_in, flash_swap) = animeswap::flash_swap<X, Y>(lps, 0, borrow_amount);
        balance::destroy_zero<X>(balance_in_zero);
        let coin_in = coin::from_balance<Y>(balance_in, ctx);
        // do something
        coins_out = f(coins_in);
        // repay X
        let repay_coins = coin::split(&mut coins_out, amount, ctx);
        animeswap::pay_flash_swap<X, Y>(lps, clock, coin::into_balance<X>(repay_coins), balance::zero<Y>(), flash_swap);
    } else {
        // flash loan Y
        let (balance_in, balance_in_zero, flash_swap) = animeswap::flash_swap<Y, X>(lps, 0, borrow_amount);
        balance::destroy_zero<X>(balance_in_zero);
        let coin_in = coin::from_balance<Y>(balance_in, ctx);
        // do something
        coins_out = f(coins_in);
        // repay X
        let repay_coins = coin::split(&mut coins_out, amount, ctx);
        animeswap::pay_flash_swap<Y, X>(lps, clock, balance::zero<Y>(), coin::into_balance<X>(repay_coins), flash_swap);
    };
}
```