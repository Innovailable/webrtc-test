#!/usr/bin/env python3

import json
import sys

report = json.load(open(sys.argv[1]))

def print_sdp(msg):
    print("==== {} by {} ====".format(msg['message']['event'], msg['sender']))
    print()
    print(msg['message']['sdp']['sdp'])

for name, data in report['clients'].items():
    print("==== Errors ====")
    print()

    errors = data['errors']

    if len(errors):
        print("{} errors:".format(name))

        for error in errors:
            print("- {}".format(error))

        print()
    else:
        print("{} has no errors".format(name))
        print()

for msg in report['signaling']:
    if msg['message']['event'] in ['offer', 'answer']:
        print_sdp(msg)

