#!/bin/bash
rm -f RUN.out RUN.err probe.log
love . > RUN.out 2> RUN.err &
LPID=$!
sleep 8
kill -9 $LPID 2>/dev/null
wait $LPID 2>/dev/null
