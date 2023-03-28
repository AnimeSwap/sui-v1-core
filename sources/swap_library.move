module defi::animeswap_library {
    use sui::math;
    use std::vector;
    use std::ascii;
    use std::type_name;

    /// Maximum of u128
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    /// When not enough amount for pool
    const ERR_INSUFFICIENT_AMOUNT: u64 = 201;
    /// When not enough liquidity amount
    const ERR_INSUFFICIENT_LIQUIDITY: u64 = 202;
    /// When not enough input amount
    const ERR_INSUFFICIENT_INPUT_AMOUNT: u64 = 203;
    /// When not enough output amount
    const ERR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 204;
    /// When two coin type is the same
    const ERR_COIN_TYPE_SAME_ERROR: u64 = 205;

    /// given some amount of an asset and pair reserves,
    /// returns an equivalent amount of the other asset.
    public fun quote(
        amount_x: u64,
        reserve_x: u64,
        reserve_y: u64
    ): u64 {
        assert!(amount_x > 0, ERR_INSUFFICIENT_AMOUNT);
        assert!(reserve_x > 0 && reserve_y > 0, ERR_INSUFFICIENT_LIQUIDITY);
        let amount_y = ((amount_x as u128) * (reserve_y as u128) / (reserve_x as u128) as u64);
        amount_y
    }

    /// given an input amount of an asset and pair reserves,
    /// returns the maximum output amount of the other asset.
    public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        swap_fee: u64
    ): u64 {
        assert!(amount_in > 0, ERR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERR_INSUFFICIENT_LIQUIDITY);
        let amount_in_with_fee = (amount_in as u128) * ((10000 - swap_fee) as u128);
        let numerator = amount_in_with_fee * (reserve_out as u128);
        let denominator = (reserve_in as u128) * 10000 + amount_in_with_fee;
        let amount_out = numerator / denominator;
        (amount_out as u64)
    }

    /// given an output amount of an asset and pair reserves,
    /// returns a required input amount of the other asset
    public fun get_amount_in(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64,
        swap_fee: u64
    ): u64 {
        assert!(amount_out > 0, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERR_INSUFFICIENT_LIQUIDITY);
        let numerator = (reserve_in as u128) * (amount_out as u128) * 10000;
        let denominator = ((reserve_out - amount_out) as u128) * ((10000 - swap_fee) as u128);
        let amount_in = numerator / denominator + 1;
        (amount_in as u64)
    }

    public fun sqrt(x: u64, y: u64): u64 {
        (math::sqrt_u128((x as u128) * (y as u128)) as u64)
    }

    /// Add but allow overflow
    public fun overflow_add(a: u128, b: u128): u128 {
        let r = MAX_U128 - b;
        if (r < a) {
            return a - r - 1
        };
        r = MAX_U128 - a;
        if (r < b) {
            return b - r - 1
        };
        a + b
    }

    // Check if mul maybe overflow
    // The result maybe false positive
    public fun is_overflow_mul(a: u128, b: u128): bool {
        MAX_U128 / b <= a
    }

    // compare type, when use, true iff: X < Y
    public fun compare<X, Y>(): bool {
        let type_name_x = type_name::into_string(type_name::get<X>());
        let type_name_y = type_name::into_string(type_name::get<Y>());

        let length_x = ascii::length(&type_name_x);
        let length_y = ascii::length(&type_name_y);

        let bytes_x = ascii::into_bytes(type_name_x);
        let bytes_y = ascii::into_bytes(type_name_y);

        if (length_x < length_y) return true;
        if (length_x > length_y) return false;

        let idx = 0;
        while (idx < length_x) {
            let byte_x = *vector::borrow(&bytes_x, idx);
            let byte_y = *vector::borrow(&bytes_y, idx);
            if (byte_x < byte_y) {
                return true
            } else if (byte_x > byte_y) {
                return false
            };
            idx = idx + 1;
        };

        assert!(false, ERR_COIN_TYPE_SAME_ERROR);
        false
    }

    #[test_only]
    const TEST_ERROR:u64 = 10000;
    #[test_only]
    struct TestCoinA {}
    #[test_only]
    struct TestCoinB {}
    #[test_only]
    struct TestCoinAA {}

    #[test]
    public entry fun test_compare() {
        let a = compare<TestCoinA, TestCoinB>();
        assert!(a == true, TEST_ERROR);
        let a = compare<TestCoinB, TestCoinAA>();
        assert!(a == true, TEST_ERROR);
        let a = compare<TestCoinAA, TestCoinA>();
        assert!(a == false, TEST_ERROR);
    }
}