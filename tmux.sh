#!/bin/bash

SESSION="test-session"

tmux -2 new-session -d -s $SESSION
tmux send-keys "/usr/sbin/tcpretrans-bpfcc" C-m
tmux split-window -h
tmux select-pane -t 0
tmux split-window -v
tmux send-keys "/usr/sbin/tcpconnlat-bpfcc" C-m
tmux select-pane -t 0
tmux split-window -v
tmux send-keys "watch -n 1 'curl -s localhost/server-status?auto | grep BusyWorkers -A99'" C-m

tmux select-pane -t 0
tmux split-window -v
tmux send-keys "watch -n 0.1 ss -tln src :80" C-m

tmux select-pane -t 4
tmux send-keys "sar -n TCP,ETCP 1" C-m
tmux split-window -v
tmux send-keys "watch -n 0.3 'nstat -az TcpExtListenDrops'" C-m
tmux select-pane -t 4
tmux split-window -v
tmux send-keys "watch -n 0.1 'ss -tn state syn-sent | wc -l'" C-m
tmux select-pane -t 4
tmux split-window -v
tmux send-keys "watch -n 0.1 'ss -tan state established dst :80 | wc -l'" C-m
tmux select-pane -t 0

tmux -2 a -t $SESSION
