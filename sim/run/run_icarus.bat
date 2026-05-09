@echo off
cd /d %~dp0

iverilog -o sim.out -I ..\..\rtl\include ..\..\rtl\core\top.v ..\..\rtl\core\compute_unit.v ..\..\rtl\warp\warp_manager.v ..\..\rtl\warp\scoreboard.v ..\..\rtl\pipeline\IFU.v ..\..\rtl\pipeline\decode_unit.v ..\..\rtl\pipeline\execute_stage.v ..\..\rtl\pipeline\mem_stage.v ..\..\rtl\pipeline\writeback_stage.v ..\..\rtl\alu\vector_alu.v ..\..\rtl\register_file\vector_register_file.v ..\..\rtl\memory\instruction_memory.v ..\..\rtl\memory\data_memory.v ..\..\tb\unit\tb_compute_unit.v

IF %ERRORLEVEL% NEQ 0 (
    echo Compilation failed
    pause
    exit /b
)

cd ..
vvp run\sim.out
pause