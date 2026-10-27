#!/usr/bin/env python3
"""Synthetic, loopback-only API for README renders; never contacts tokens.ci."""
import datetime as dt
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

TODAY = dt.datetime.now(dt.timezone.utc).date()
NAMES = ['claude-opus-4-6', 'gpt-5.4', 'claude-sonnet-4-6', 'gemini-3.1-pro', 'gpt-5.4-mini']
WEIGHTS = [46, 28, 18, 7, 1]
contributions = []
for i in range(365):
    day = TODAY - dt.timedelta(days=364-i)
    active = i % 7 not in (0, 6) or i > 355
    tokens = (3_100_000 + ((i*7919) % 9_600_000)) if active else 0
    if i == 364:
        tokens = 12_400_000
    cost = round(tokens / 1_000_000 * 1.25, 2)
    models = {name: {'tokens': tokens*w//100, 'cost': round(cost*w/100, 2)} for name, w in zip(NAMES, WEIGHTS)}
    contributions.append({'date': day.isoformat(), 'intensity': 1 + i % 4 if active else 0,
        'totals': {'tokens': tokens, 'cost': cost, 'messages': tokens//32000},
        'clients': [{'client': 'claude-code', 'tokens': {'input': tokens}, 'cost': cost,
                     'messages': tokens//32000, 'models': models}] if active else []})
total = sum(d['totals']['tokens'] for d in contributions)
cost = round(sum(d['totals']['cost'] for d in contributions), 2)
profile = {'user': {'username': 'demo-user', 'rank': 87},
    'stats': {'totalTokens': total, 'totalCost': cost, 'activeDays': sum(d['totals']['tokens'] > 0 for d in contributions)},
    'modelUsage': [{'model': n, 'tokens': total*w//100, 'cost': round(cost*w/100, 2)} for n,w in zip(NAMES, WEIGHTS)],
    'contributions': contributions,
    'chartRange': {'start': contributions[0]['date'], 'end': contributions[-1]['date']},
    'updatedAt': TODAY.isoformat()+'T08:00:00Z',
    'submissionFreshness': {'isStale': False}}
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlparse(self.path)
        if url.path == '/api/users/demo-user':
            body = profile
        elif url.path == '/api/leaderboard':
            daily = parse_qs(url.query).get('period') == ['today']
            rank, amount = (31, 12_400_000) if daily else (87, total)
            body = {'users': [{'rank': rank-1, 'username': 'sample-neighbour', 'totalTokens': amount+2_600_000},
                              {'rank': rank, 'username': 'demo-user', 'totalTokens': amount}],
                    'pagination': {'totalUsers': 265, 'hasNext': False}}
        else:
            self.send_error(404); return
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers(); self.wfile.write(data)
ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
