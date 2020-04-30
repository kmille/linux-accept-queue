# Hands-On: How does the Accept-Queue work on Linux?


https://web.archive.org/web/*/https://blog.cloudflare.com/syn-packet-handling-in-the-wild/


# Explation of the setup

# Explation of the tmux panes
0 /usr/sbin/tcpretrans-bpfcc  
- shows tretransmitted packages
- is part of the bcc tools: https://github.com/iovisor/bcc
- insallation: sudo apt-get install bpfcc-tools linux-headers-$(uname -r)
- Explanation: https://github.com/iovisor/bcc/blob/master/tools/tcpretrans_example.txt

1 watch -n 0.1 ss -tln src :80
- shows us the backlog parameter
- shows us the the length of the accept queue

2 watch -n 1 'curl -s localhost/server-status?auto | grep BusyWorkers -A99'
- shows us the workload of apache

3 /usr/sbin/tcpconnlat-bpfcc

4 sar -n TCP,ETCP 1
- shows network statistics. We are interested in:
    - active/s
    - passive/s
    - retrans/s


              active/s
                     The number of times TCP connections have made a direct transition to the SYN-SENT state from the CLOSED state per second [tcpActiveOpens].

              passive/s
                     The number of times TCP connections have made a direct transition to the SYN-RCVD state from the LISTEN state per second [tcpPassiveOpens].

              retrans/s
                     The  total number of segments retransmitted per second - that is, the number of TCP segments transmitted containing one or more previously transmitted octets [tcpRe‐
                     transSegs].



5 watch -n 0.1 'ss -tan state established dst :80 | wc -l'
- shows the amount of established tcp connetions for port 80

6 watch -n 0.1 'ss -tn state syn-sent | wc -l'
- shows the amount of tcp connections in state syn-sent
- syn-sent means: I sent you a SYN but have not received a SYN/ACK so far
 
7 watch -n 0.3 'nstat -az TcpExtListenDrops'
- system wide counter the shows how many packets are dropped


# Round #1: idle
[![asciicast](https://asciinema.org/a/325486.svg)](https://asciinema.org/a/325486)
What we see here is:
- in tmux pane 2 curl sends every second a request to get the state of apache's scoreboard
- sar shows use 1 active/s and 1 passive/s, no retransmits
- the both ss commands in tmux pane 5 and 6 are lying
    - the output 1 is is just the header ss prints
    - in pane 5 there should be a 2 (1 line header + line for the established connection by curl)
        - probobly the connection is too fast to be shown here
- the latency is around 0.05 ms which is pretty short but it's just localhost
- the 44720 connection come from my previous expermiments :)


# Round #2: sending 50 concurrent requests
[![asciicast](https://asciinema.org/a/V6iawgVpHYQuCGXD0Ht5fgVf5.svg)](https://asciinema.org/a/V6iawgVpHYQuCGXD0Ht5fgVf5)
What we see here is:
- 51 connections in state establised (1x curl scoreboard and 50x ab)
- 51 busy apache worker
- the latancy is almost the same
- the accept queue is still 0 because the apache+php-fpm is fast enough to cope the 50 requests
- sar shows
    - after ab was started there were 50 outgoing and 50 incoming requests (+ 1 curl request every second)
    - if apache+php-fpm processed some requests ab will send new packets so that ther are always 50 concurrent connections
- to check: active/s and passiv/s are always the same
    use 1 active/s and 1 passive/s, no retransmits
- my manually entered curl jus worked immediatly


# Round #3: sending 200 concurrent requests
[![asciicast](https://asciinema.org/a/325488.svg)](https://asciinema.org/a/325488)
Things are getting excited! What we see here is:
- sar -tn state establised shows 201 established tcp connections 
- the apache scoreboard hangs because apache is not fast enough to respond in one second
    - after some while we get some information out of the scoreboard:
        - apache has around 150 busy worker
        - we are sending 200 requests with ab
        - that means: there are  around 50 requests which cannot be handled by the application (apache+php-fpm is too slow)
        - that's why we see around 50 requests in the accept queue pending
- Let's look at my manually executed curl request
    - it requests a static file. So php-fpm cannot be the bottleneck
    - the tcp connection is established immeidatly
    - curl sends the acutal request
    - as the apache+php-fpm are currently full with work => the packet will be queued to the accept queue
    - after some time the request gets served by apache

- latency is still low
- we don't have any drops or retransmissions here

# Round #4: sending 1000 concurrent requests
[![asciicast](https://asciinema.org/a/325489.svg)](https://asciinema.org/a/325489)
Prepare for kernel drops! What we see here is:
- check: use can the see IdleWorkers of apache are 224 => not my first try
- apache scoreboard we see basically to states:
    - before calling ab: the IdleWorkers increased to 224 in the meantime (because of the my previous load tests. not captured here in this blog post)
    - after calling ab: 255 BusyWorkers
- There are around 480 establised

