#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import threading

ROOT = Path(__file__).resolve().parents[2]
DEFAULTS = dict(resolve=300, test=300, build=600, metadata=30, trial=120,
                readiness=10, sample=20, conversion=30, validation=30, target=90, entire=1800)

class Collection:
    def __init__(self, out, limits):
        self.out = Path(out).resolve()
        self.out.mkdir(parents=True, exist_ok=False)
        self.limits = limits
        self.started = time.monotonic()
        self.stages = []
        self.owned = []
        self.sockets = []
        self.save()

    def save(self):
        (self.out / 'stages.json').write_text(json.dumps(dict(deadlines=self.limits, stages=self.stages), indent=2))

    def record(self, name, start, code, status=None):
        self.stages.append(dict(name=name, elapsed=time.monotonic()-start, exit_status=code,
                                status=status or ('passed' if code == 0 else 'failed')))
        self.save()

    def stop(self, process):
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        # The leader may exit before its children; retain ownership of the group.
        end = time.monotonic() + 5
        while time.monotonic() < end:
            try:
                os.killpg(process.pid, 0)
            except ProcessLookupError:
                break
            time.sleep(.05)
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()

    def run(self, name, command, kind, stdin=None):
        start = time.monotonic()
        remaining = self.limits['entire'] - (start-self.started)
        with (self.out / (name+'.log')).open('wb') as log:
            try:
                process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                           stdin=stdin, start_new_session=True)
            except OSError:
                self.record(name, start, None, 'blocked')
                raise
            self.owned.append(process)
            try:
                code = process.wait(timeout=max(.001, min(self.limits[kind], remaining)))
            except subprocess.TimeoutExpired:
                self.stop(process)
                self.record(name, start, process.returncode, 'timed-out')
                raise RuntimeError(name+' timed out')
            self.record(name, start, code)
            if code:
                raise RuntimeError(name+' failed')
        return (self.out / (name+'.log')).read_text(errors='replace')

    def cleanup(self):
        for process in self.owned:
            self.stop(process)
        for socket in self.sockets:
            socket.unlink(missing_ok=True)

    def profile(self, binary, layout):
        directory = self.out / ('profile-'+layout)
        directory.mkdir()
        settings = dict(numberOfSamples=500, timeInterval='10ms')
        (directory/'request.json').write_text(json.dumps(settings))
        start = time.monotonic()
        env = os.environ.copy()
        env.pop('PROFILE_RECORDER_SERVER_URL', None)
        env['PROFILE_RECORDER_SERVER_URL_PATTERN'] = 'unix:///tmp/chroma-profile-{PID}.sock'
        with (directory/'process.log').open('wb') as log:
            target = subprocess.Popen([binary, '--layout', layout, '--workload', 'scroll',
                                       '--replay-seconds', '30'], env=env, cwd=ROOT,
                                      stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            self.owned.append(target)
            expired = threading.Event()
            def expire():
                expired.set()
                self.stop(target)
            watchdog = threading.Timer(max(.001, min(self.limits["target"], self.limits["entire"]-(time.monotonic()-self.started))), expire)
            watchdog.start()
            socket = Path('/tmp/chroma-profile-'+str(target.pid)+'.sock')
            self.sockets.append(socket)
            (directory/'target.json').write_text(json.dumps(dict(pid=target.pid, socket=str(socket), replay_seconds=30)))
            try:
                deadline = time.monotonic()+self.limits['readiness']
                ready = False
                while time.monotonic() < deadline and target.poll() is None:
                    try:
                        self.run('health-'+layout+'-'+str(len(self.stages)),
                                 ['curl', '-fsS', '--connect-timeout', '2', '--max-time', str(max(.001, min(2, deadline-time.monotonic()))),
                                  '--unix-socket', str(socket), 'http://localhost/health'], 'readiness')
                        ready = True
                        break
                    except RuntimeError:
                        time.sleep(.1)
                if not ready:
                    raise RuntimeError('profile readiness deadline')
                raw = directory/'samples.raw.perf'
                self.run('sample-'+layout, ['curl', '-fsS', '--connect-timeout', '2', '--max-time', str(self.limits['sample']),
                         '--unix-socket', str(socket), '-H', 'Content-Type: application/json', '--data', json.dumps(settings),
                         'http://localhost/sample', '--output', str(raw)], 'sample')
                with raw.open('rb') as source:
                    self.run('demangle-'+layout, ['swift', 'demangle', '--compact'], 'conversion', stdin=source)
                (directory/'samples.perf').write_bytes((self.out/('demangle-'+layout+'.log')).read_bytes())
                self.run('validate-'+layout, [sys.executable, str(Path(__file__)), '--validate', str(directory/'samples.perf')], 'validation')
                target.wait(timeout=max(.001, min(self.limits['target']-(time.monotonic()-start),
                                                   self.limits['entire']-(time.monotonic()-self.started))))
                if expired.is_set():
                    self.record('target-'+layout, start, target.returncode, 'timed-out')
                    raise RuntimeError('target deadline')
                self.record('target-'+layout, start, target.returncode)
                if target.returncode:
                    raise RuntimeError('target failed')
            except Exception:
                self.record('target-'+layout, start, target.poll(), 'blocked')
                raise
            finally:
                watchdog.cancel()
                watchdog.join()
                self.stop(target)
                socket.unlink(missing_ok=True)

    def collect(self):
        self.run('snapshot', ['sh', '-c', 'git ls-files -co --exclude-standard -z | tar --null -T - -czf "$1"',
                             'sh', str(self.out/'source.tar.gz')], 'metadata')
        for name, cmd in [('revision', ['git','rev-parse','HEAD']), ('worktree',['git','status','--short']),
                          ('diff',['git','diff']), ('toolchain',['swift','--version']),
                          ('hardware',['sh','-c','uname -a; if command -v lscpu >/dev/null; then lscpu; else sysctl -a; fi'])]:
            self.run(name, cmd, 'metadata')
        self.run('resolve', ['swift','package','--package-path','Benchmarks','resolve'], 'resolve')
        (self.out/'Package.resolved').write_bytes((ROOT/'Benchmarks/Package.resolved').read_bytes())
        for package in ['.', 'Examples', 'Benchmarks']:
            self.run('test-'+package.replace('.', 'core'), ['swift','test','--package-path',package], 'test')
        flags = ['-c','release','--product','InteractionBenchmark','-Xswiftc','-g']
        (self.out/'settings.json').write_text(json.dumps(dict(build_flags=flags, rows=1000, events=8,
            viewport=[400,600], warmups=5, measured_frames=30, trials=3, diagnostics='off', backend_submission='not-applicable'), indent=2))
        self.run('build', ['swift','build','--package-path','Benchmarks']+flags, 'build')
        path = self.run('binary-path',['swift','build','--package-path','Benchmarks','-c','release','--show-bin-path'], 'metadata').strip()
        binary = str(Path(path)/'InteractionBenchmark')
        for trial in range(1,4):
            self.run('trial-'+str(trial), [binary], 'trial')
        self.run('diagnostics', [binary,'--diagnostics','on'], 'trial')
        blockers = []
        for layout in ['eager','lazy']:
            try:
                self.profile(binary, layout)
            except Exception as error:
                blockers.append(layout+': '+str(error))
        (self.out/'completion.json').write_text(json.dumps(dict(status='baseline-ready-with-profile-blocker' if blockers else 'baseline-ready',
            profile_blockers=blockers), indent=2))


def validate(path):
    text = Path(path).read_text()
    import re
    headers = re.findall(r'^.+\s+\d+(?:/\d+)?\s+\d+\.\d+:', text, re.M)
    frames = [line for line in text.splitlines() if re.match(r'^\s+[0-9a-f]+\s', line)]
    recognizable = [line for line in frames if any(word in line for word in ['Chroma', 'InteractionBenchmark', 'BlockEngine', 'ScrollView'])]
    result = dict(sample_headers=len(headers), frames=len(frames), workload_frames=len(recognizable),
                  unresolved_frames=sum('unknown' in line.lower() or '???' in line for line in frames))
    print(json.dumps(result, indent=2))
    if not headers or not recognizable:
        raise RuntimeError('missing actual samples or recognizable workload stacks')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('out', nargs='?')
    parser.add_argument('--validate')
    args = parser.parse_args()
    if args.validate:
        validate(args.validate)
    else:
        limits = {key: float(os.environ.get('CHROMA_DEADLINE_'+key.upper(), value)) for key,value in DEFAULTS.items()}
        collection = Collection(args.out, limits)
        def interrupted(*_):
            raise KeyboardInterrupt()
        signal.signal(signal.SIGTERM, interrupted)
        signal.signal(signal.SIGINT, interrupted)
        watchdog = threading.Timer(limits["entire"], lambda: os.kill(os.getpid(), signal.SIGTERM))
        watchdog.start()
        try:
            collection.run("script-tests", [sys.executable, str(Path(__file__).with_name("test_collect_phase1.py"))], "validation")
            collection.collect()
        finally:
            watchdog.cancel()
            watchdog.join()
            collection.cleanup()
