#!/usr/bin/env python3
"""
ACMOJ Client for submitting and checking OJ submissions.
"""

import os
import sys
import requests
import time
import json

# Configuration
ACMOJ_TOKEN = os.environ.get('ACMOJ_TOKEN', 'acmoj-9b29d13570991798b3299bc41a016b87')
ACMOJ_PROBLEM_ID = os.environ.get('ACMOJ_PROBLEM_ID', '2531')
ACMOJ_API_BASE = 'https://acm.sjtu.edu.cn/OnlineJudge/api'

def submit_solution(repo_url):
    """Submit a solution to ACMOJ."""
    headers = {
        'Authorization': f'Bearer {ACMOJ_TOKEN}',
        'Content-Type': 'application/json'
    }

    data = {
        'problem_id': ACMOJ_PROBLEM_ID,
        'repository_url': repo_url,
        'language': 'verilog'
    }

    try:
        response = requests.post(
            f'{ACMOJ_API_BASE}/submit',
            headers=headers,
            json=data,
            timeout=30
        )
        response.raise_for_status()
        result = response.json()
        print(f"Submission successful!")
        print(f"Submission ID: {result.get('submission_id', 'N/A')}")
        return result.get('submission_id')
    except requests.exceptions.RequestException as e:
        print(f"Error submitting solution: {e}")
        if hasattr(e.response, 'text'):
            print(f"Response: {e.response.text}")
        return None

def check_status(submission_id):
    """Check the status of a submission."""
    headers = {
        'Authorization': f'Bearer {ACMOJ_TOKEN}',
    }

    try:
        response = requests.get(
            f'{ACMOJ_API_BASE}/submission/{submission_id}',
            headers=headers,
            timeout=30
        )
        response.raise_for_status()
        result = response.json()

        status = result.get('status', 'Unknown')
        print(f"\nSubmission ID: {submission_id}")
        print(f"Status: {status}")

        if 'score' in result:
            print(f"Score: {result['score']}")

        if 'test_results' in result:
            print(f"\nTest Results:")
            for test in result['test_results']:
                print(f"  Test {test.get('test_id', 'N/A')}: {test.get('result', 'N/A')}")

        if 'message' in result:
            print(f"\nMessage: {result['message']}")

        if 'error' in result:
            print(f"\nError: {result['error']}")

        return result
    except requests.exceptions.RequestException as e:
        print(f"Error checking status: {e}")
        if hasattr(e.response, 'text'):
            print(f"Response: {e.response.text}")
        return None

def abort_submission(submission_id):
    """Abort a pending submission."""
    headers = {
        'Authorization': f'Bearer {ACMOJ_TOKEN}',
    }

    try:
        response = requests.post(
            f'{ACMOJ_API_BASE}/submission/{submission_id}/abort',
            headers=headers,
            timeout=30
        )
        response.raise_for_status()
        print(f"Submission {submission_id} aborted successfully")
        return True
    except requests.exceptions.RequestException as e:
        print(f"Error aborting submission: {e}")
        if hasattr(e.response, 'text'):
            print(f"Response: {e.response.text}")
        return False

def wait_for_result(submission_id, max_wait_seconds=300, check_interval=10):
    """Wait for submission result with periodic status checks."""
    print(f"\nWaiting for submission {submission_id} to complete...")
    start_time = time.time()

    while time.time() - start_time < max_wait_seconds:
        result = check_status(submission_id)

        if result:
            status = result.get('status', '').lower()
            if status in ['accepted', 'wrong answer', 'time limit exceeded',
                         'runtime error', 'compile error', 'system error', 'completed']:
                print(f"\nFinal result received!")
                return result

        print(f"\nWaiting {check_interval} seconds before next check...")
        time.sleep(check_interval)

    print(f"\nTimeout waiting for result after {max_wait_seconds} seconds")
    print(f"You can abort this submission with: python {sys.argv[0]} abort {submission_id}")
    return None

def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print(f"  {sys.argv[0]} submit <repo_url>        - Submit solution")
        print(f"  {sys.argv[0]} status <submission_id>   - Check submission status")
        print(f"  {sys.argv[0]} abort <submission_id>    - Abort pending submission")
        print(f"  {sys.argv[0]} wait <submission_id>     - Wait for submission result")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == 'submit':
        if len(sys.argv) < 3:
            print("Error: Repository URL required")
            print(f"Usage: {sys.argv[0]} submit <repo_url>")
            sys.exit(1)
        repo_url = sys.argv[2]
        submission_id = submit_solution(repo_url)
        if submission_id:
            print(f"\nTo check status, run:")
            print(f"  python {sys.argv[0]} status {submission_id}")
            print(f"  python {sys.argv[0]} wait {submission_id}")

    elif command == 'status':
        if len(sys.argv) < 3:
            print("Error: Submission ID required")
            print(f"Usage: {sys.argv[0]} status <submission_id>")
            sys.exit(1)
        submission_id = sys.argv[2]
        check_status(submission_id)

    elif command == 'abort':
        if len(sys.argv) < 3:
            print("Error: Submission ID required")
            print(f"Usage: {sys.argv[0]} abort <submission_id>")
            sys.exit(1)
        submission_id = sys.argv[2]
        abort_submission(submission_id)

    elif command == 'wait':
        if len(sys.argv) < 3:
            print("Error: Submission ID required")
            print(f"Usage: {sys.argv[0]} wait <submission_id>")
            sys.exit(1)
        submission_id = sys.argv[2]
        wait_for_result(submission_id)

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == '__main__':
    main()
