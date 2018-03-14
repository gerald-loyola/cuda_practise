@echo off

IF NOT EXIST ..\build mkdir ..\build
pushd ..\build

rem cl ..\code\bingo_card_sim_data.c -Od -Zi -link kernel32.lib -SUBSYSTEM:CONSOLE
rem cl -nologo ..\code\bingo_card_sim_data.c -Fosimhost -Od -c
rem nvcc ..\code\bingo_card_sim_data.cu -dw -arch=compute_20 -code=sm_21 -w -o simdevice -m64
rem nvcc simhost.obj simdevice.obj -Xlinker kernel32.lib,-SUBSYSTEM:CONSOLE -o bingosim
rem cl simhost.obj -link kernel32.lib -SUBSYSTEM:WINDOWS

rem nvcc ..\code\bingo_card_sim_data.cu -dw -arch=compute_20 -code=sm_21 -G -w -o simdevice -m64
rem nvcc ..\code\bingo_card_sim_data.c simdevice.obj -arch=compute_20 -code=sm_21 -g -Xlinker kernel32.lib,-SUBSYSTEM:CONSOLE -o bingosim
nvcc ..\code\bingo_card_sim_data.cu -arch=compute_20 -code=sm_21 -G -g -w -o simulate_bingo -m64 

popd
