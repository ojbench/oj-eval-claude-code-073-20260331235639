#!/usr/bin/env python3
"""
ACMOJ Client for submitting and checking OJ submissions.

NOTE: API endpoint discovery attempts have been unsuccessful.
The standard ACMOJ API endpoints redirect to login pages and
do not accept Bearer token authentication.

Current implementation status:
- RISC-V CPU with RV32I instruction set: COMPLETE
- All 37 required instructions: IMPLEMENTED
- I/O handling (0x30000, 0x30004): IMPLEMENTED
- Supporting modules (RAM, UART): IMPLEMENTED
- Basic testbench: IMPLEMENTED

Repository: https://github.com/ojbench/oj-eval-claude-code-073-20260331235639
Latest commit: d307d4b

The code has been pushed to GitHub and is ready for evaluation.
"""

import os
import sys
import requests
import time
import json

# Configuration
ACMOJ_TOKEN = os.environ.get('ACMOJ_TOKEN', 'acmoj-9b29d13570991798b3299bc41a016b87')
ACMOJ_PROBLEM_ID = os.environ.get('ACMOJ_PROBLEM_ID', '2531')
REPO_URL = "https://github.com/ojbench/oj-eval-claude-code-073-20260331235639"

# Possible API bases
API_BASES = [
    'https://acm.sjtu.edu.cn',
    'https://oj.sjtu.edu.cn',
    'https://api.acm.sjtu.edu.cn',
]

def try_submit(repo_url):
    """Attempt to submit using various known API patterns."""

    print(f"\nAttempting submission to ACMOJ...")
    print(f"Problem ID: {ACMOJ_PROBLEM_ID}")
    print(f"Repository: {repo_url}\n")

    # Try different endpoint patterns
    endpoints = [
        "/api/submit",
        "/api/judge/submit",
        "/api/submissions",
        f"/api/problem/{ACMOJ_PROBLEM_ID}/submit",
    ]

    headers = {
        'Authorization': f'Bearer {ACMOJ_TOKEN}',
        'Content-Type': 'application/json'
    }

    data = {
        'problem_id': ACMOJ_PROBLEM_ID,
        'repository_url': repo_url,
    }

    for base in API_BASES:
        for endpoint in endpoints:
            url = base + endpoint
            try:
                print(f"Trying: {url}")
                response = requests.post(url, headers=headers, json=data, timeout=10, allow_redirects=False)

                if response.status_code in [200, 201, 202]:
                    print(f"\n✓ SUCCESS!")
                    print(f"Status: {response.status_code}")
                    result = response.json()
                    print(f"Response: {json.dumps(result, indent=2)}")
                    return result.get('submission_id')
                elif response.status_code not in [302, 303, 404, 405]:
                    print(f"  Status: {response.status_code}")
                    print(f"  Response: {response.text[:200]}")
            except Exception as e:
                pass

    print("\n" + "="*70)
    print("⚠ Could not find working submission endpoint")
    print("="*70)
    print("\nThe API endpoints tested do not accept the provided authentication.")
    print("Possible reasons:")
    print("1. The OJ system monitors the GitHub repository automatically")
    print("2. A different authentication mechanism is required")
    print("3. The evaluation system uses a different API structure")
    print("\nYour code has been pushed to GitHub:")
    print(f"  {repo_url}")
    print("\nIf the system monitors repositories, evaluation may occur automatically.")
    return None

def check_status(submission_id):
    """Check the status of a submission."""
    print(f"\nChecking status of submission: {submission_id}")

    headers = {
        'Authorization': f'Bearer {ACMOJ_TOKEN}',
    }

    for base in API_BASES:
        endpoints = [
            f"/api/submission/{submission_id}",
            f"/api/submissions/{submission_id}",
        ]

        for endpoint in endpoints:
            url = base + endpoint
            try:
                response = requests.get(url, headers=headers, timeout=10)
                if response.status_code == 200:
                    result = response.json()
                    print(f"\nStatus: {result.get('status', 'Unknown')}")
                    if 'score' in result:
                        print(f"Score: {result['score']}")
                    if 'message' in result:
                        print(f"Message: {result['message']}")
                    return result
            except:
                pass

    print("Could not retrieve submission status")
    return None

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        print("\nUsage:")
        print(f"  {sys.argv[0]} submit [repo_url]        - Submit solution")
        print(f"  {sys.argv[0]} status <submission_id>   - Check submission status")
        print(f"\nDefault repository: {REPO_URL}")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == 'submit':
        repo_url = sys.argv[2] if len(sys.argv) > 2 else REPO_URL
        submission_id = try_submit(repo_url)
        if submission_id:
            print(f"\nSubmission ID: {submission_id}")
        else:
            print("\nNote: Code has been pushed to GitHub and is ready for evaluation.")

    elif command == 'status':
        if len(sys.argv) < 3:
            print("Error: Submission ID required")
            print(f"Usage: {sys.argv[0]} status <submission_id>")
            sys.exit(1)
        submission_id = sys.argv[2]
        check_status(submission_id)

    else:
        print(f"Unknown command: {command}")
        print("Use 'submit' or 'status'")
        sys.exit(1)

if __name__ == '__main__':
    main()
