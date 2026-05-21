# APB Verification (SystemVerilog + UVM)

UVM verification environment for an **APB slave register file** DUT, following the AMBA APB setup/access protocol.

## Structure

```
rtl/                    APB slave DUT (4 x 32-bit registers)
tb/
  apb_if.sv             Virtual interface
  apb_pkg.sv            UVM components, sequences, tests
  env/                  Agent, scoreboard, reference model, coverage
  seq/                  Directed and random sequences
  tests/                UVM test classes
  tb_top.sv             Top testbench
  apb_assertions.sv     Protocol assertions (bound to DUT)
sim/
  Makefile              Questa / Xcelium flows
  filelist.f            Compile file list
  run.ps1               Windows runner script
```

## Prerequisites

- **Questa** or **ModelSim** (Intel FPGA edition includes Questa)
- UVM 1.2 (bundled with Questa at `$QUESTA_HOME/verilog_src/uvm-1.2`)

Set environment variables:

```powershell
$env:QUESTA_HOME = "C:\intelFPGA_lite\23.1std\questa_fe"
$env:PATH += ";$env:QUESTA_HOME\win64"
```

## Run simulation

```powershell
cd sim
.\run.ps1 -Test apb_sanity_test
.\run.ps1 -All
```

Or with Make (Git Bash / WSL / Linux):

```bash
cd sim
make compile
make run TEST=apb_sanity_test
make run-all
```

## Tests

| Test | Description |
|------|-------------|
| `apb_sanity_test` | Single write/read to register 0 |
| `apb_reg_test` | Walk all four registers |
| `apb_random_test` | Constrained-random traffic |
| `apb_error_test` | Illegal addresses (expects `pslverr`) |

## Verification features

- Active UVM master agent (driver, monitor, sequencer)
- Scoreboard with reference register model
- Functional coverage (kind, address, `pslverr`, idle cycles)
- SVA checks for SETUP-before-ACCESS and stable select until `pready`
- Configurable `pready` wait states in the DUT

## License

See [LICENSE](LICENSE).
