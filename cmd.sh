sui client publish --gas-budget 10000

sui client call \
--package 0x7b643e56614f58ff78a0c49799c62cd2d209eef7 \
--module animeswap \
--function create_pair_entry \
--gas-budget 10000 \
--type-args \
0xa556d7170e3a2dc369e5553db6e341793cf5a9fe::testcoin1::TESTCOIN1 \
0xa556d7170e3a2dc369e5553db6e341793cf5a9fe::testcoin2::TESTCOIN2

sui client call \
--package 0x7b643e56614f58ff78a0c49799c62cd2d209eef7 \
--module animeswap \
--function add_liquidity_entry \
--gas-budget 10000 \
--type-args \
0xa556d7170e3a2dc369e5553db6e341793cf5a9fe::testcoin1::TESTCOIN1 \
0xa556d7170e3a2dc369e5553db6e341793cf5a9fe::testcoin2::TESTCOIN2 \
--args \
0xf06ff22f9e2d277accac1e8196ce7f464e491670 \
0x9625ac8b23f6366eb172942a48ab071e6b898ef7 \
0x28c054e887ecc5f6828c99a5ebde9a21e9452091 \
1000000000000 1000000000000 1 1

sui client call \
--package 0x7b643e56614f58ff78a0c49799c62cd2d209eef7 \
--module animeswap \
--function swap_exact_coins_for_coins_x_y \
--gas-budget 10000 \
--type-args \
0xa556d7170e3a2dc369e5553db6e341793cf5a9fe::testcoin1::TESTCOIN1 \
0xa556d7170e3a2dc369e5553db6e341793cf5a9fe::testcoin2::TESTCOIN2 \
--args \
0xf06ff22f9e2d277accac1e8196ce7f464e491670 \
0x8220f9ed5dda7c336ee81d8dfc4e1b82cb82f1f3 \
500000000000 1

sui client call \
--package 0x7b643e56614f58ff78a0c49799c62cd2d209eef7 \
--module animeswap \
--function swap_coins_for_exact_coins_y_x \
--gas-budget 10000 \
--type-args \
0xa556d7170e3a2dc369e5553db6e341793cf5a9fe::testcoin1::TESTCOIN1 \
0xa556d7170e3a2dc369e5553db6e341793cf5a9fe::testcoin2::TESTCOIN2 \
--args \
0xf06ff22f9e2d277accac1e8196ce7f464e491670 \
0x6df874e2ed23962277a5cbc681ad4f2bcfbe5307 \
250000000000 1000000000000