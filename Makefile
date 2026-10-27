# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
update:; forge update

# Build & test
build  :; forge build --sizes
test   :; forge test -vvv

# Utilities
download :; cast etherscan-source --chain ${chain} -d src/etherscan/${chain}_${address} ${address}
git-diff :
	@mkdir -p diffs
	@npx prettier ${before} ${after} --write
	@git diff --no-index --diff-algorithm=patience --ignore-space-at-eol ${before} ${after} | \
	awk 'BEGIN { in_diff_block = 0; skip_block = 0; buffer = "" } \
		/^diff --git/ { \
			if (in_diff_block && skip_block == 0) { printf "%s", buffer } \
			in_diff_block = 1; skip_block = 0; buffer = $$0 "\n" \
		} \
		/similarity index 100%/ { skip_block = 1 } \
		{ if (in_diff_block && !/^diff --git/) { buffer = buffer $$0 "\n" } } \
		END { if (in_diff_block && skip_block == 0) { printf "%s", buffer } }' > diffs/${out}.diff

deploy-ledger :; forge script $(if $(filter zksync,${chain}),--zksync) ${contract} --rpc-url ${chain} $(if ${dry},--sender 0x73AF3bcf944a6559933396c1577B257e2054D935 -vvvv, --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --verify -vvvv --slow --broadcast) $(if ${legacy}, --legacy, )
deploy-pk :; forge script $(if $(filter zksync,${chain}),--zksync) ${contract} --rpc-url ${chain} $(if ${dry},--sender 0x73AF3bcf944a6559933396c1577B257e2054D935 -vvvv, --private-key ${PRIVATE_KEY} --verify -vvvv --slow --broadcast)

VERIFIER_ink = --verifier blockscout --verifier-url 'https://explorer.inkonchain.com/api/'
VERIFIER_xLayer = --verifier oklink --verifier-url 'https://www.oklink.com/api/v5/explorer/contract/verify-source-code-plugin/xlayer'
#  --resume --verify --etherscan-api-key ${ETHERSCAN_API_KEY_ARBITRUM}
deploy :; forge script script/Deploy.s.sol:Deploy${chain} --rpc-url ${chain} --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --slow --broadcast --verify $(VERIFIER_$(chain)) $(if ${resume}, --resume, )
deploy-lido :; forge script script/Deploy.s.sol:Deploylido --rpc-url mainnet --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --slow --broadcast --verify
