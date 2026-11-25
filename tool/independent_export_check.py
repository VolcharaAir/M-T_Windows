"""Independent test runner for the exported real Markov->Turing machine JSON.
Requires only Python stdlib, does not execute Dart source code.
"""
import json, itertools, collections, random, pathlib, time
ROOT = pathlib.Path(__file__).resolve().parents[1]

def load_machine(path):
    data=json.loads((ROOT/path).read_text())
    transitions={}
    for tr in data['transitions']:
        key=(tr['state'], tr['read'])
        assert key not in transitions, f'duplicate {key}'
        transitions[key]=(tr['nextState'],tr['write'],tr['move'])
    return data, transitions

def simulate(data, transitions, word, maxsteps=200000):
    tape={0:data['left']}; tape.update({i+1:ord(c) for i,c in enumerate(word)})
    state=data['initial']; head=data.get('initialHead',1 if data.get('version')==2 else 0); halts=set(data['halts'])
    for steps in range(maxsteps+1):
        if state in halts:
            if tape.get(0)!=data['left']: return ('bad_sigma', None, steps, head)
            occupied=[k for k,v in tape.items() if v not in (data['blank'],data['left'])]
            if occupied and (min(occupied)<1 or max(occupied)!=len(occupied)):
                return ('holes', None, steps, head)
            w=''.join(chr(tape[i]) for i in range(1,len(occupied)+1))
            return ('halted', w, steps, head)
        if steps>=maxsteps: return ('limit', None, steps, head)
        transition=transitions.get((state,tape.get(head,data['blank'])))
        if transition is None:return ('undefined', None, steps, head)
        newstate, write, move=transition
        if write==data['blank']:tape.pop(head,None)
        else: tape[head]=write
        head+= {'R':1,'L':-1,'S':0,'—':0}[move]
        state=newstate
    raise AssertionError('unreachable')

def check_structure(data, trans, expected_work=None, expected_trans=None):
    states={s['id'] for s in data['states']}; halts=set(data['halts'])
    assert data['initial'] in states and halts <=states
    assert all(s in states and t[0] in states for (s,_),t in trans.items())
    assert all(s not in halts for s,_ in trans)
    assert all(t[2] in ('L','R','S','—') for t in trans.values())
    assert data['initial']=='S_1' if data['version']==3 else True
    if expected_work is not None: assert len(states-halts)==expected_work
    if expected_trans is not None: assert len(trans)==expected_trans
    return len(states),len(trans)

def markov_run(rules,word, maxsteps=200):
    # Each tuple is (lhs, rhs, terminal)
    for step in range(maxsteps):
        for left,right,terminal in rules:
            at=word.find(left)
            if at < 0:continue
            word=word[:at]+right+word[at+len(left):]
            if terminal: return ('halted',word,step+1)
            break
        else: return ('halted',word,step)
    return ('limit',None,maxsteps)

def words(a, n):
    for k in range(n+1):
        yield from (''.join(s) for s in itertools.product(a,repeat=k))

def main():
    begin=time.monotonic()
    tests=collections.Counter()
    failures=[]
    fn='docs/optimized-machine.json'
    d,t=load_machine(fn)
    print('optimized machine:', check_structure(d,t,2,4))
    assert set(d['inputAlphabet'])=={48,49}
    for word in words('01',12):
        status, out, steps, head=simulate(d,t,word,500)
        expected=word.replace('1','0')
        tests['optimized_binary_exhaustive']+=1
        if (status,out,steps,head)!=('halted',expected,len(word)+2,len(word)+1):
            failures.append((fn, word, status,out,expected,steps,head))
    randomizer=random.Random(10091)
    for size in (100,1000,4000):
        for j in range(15):
            word=''.join(randomizer.choices('01',k=size))
            status,out,steps,head=simulate(d,t,word,size+10)
            tests['optimized_long_words']+=1
            if (status,out,steps,head)!=('halted',word.replace('1','0'),size+2,size+1):
                failures.append((fn,size,status,out,steps,head))
    # Legacy universal machine exported with repository, not newly compiled.
    old='examples/priority_machine.json'
    d,t=load_machine(old)
    print('legacy priority example:', check_structure(d,t))
    rules=[('00','1',False),('11','0',True)]  # Legacy JSON only contains rules 1-2
    for word in words('01',8):
        m_status,expected,msteps=markov_run(rules,word)
        status,out,steps,head=simulate(d,t,word,200000)
        tests['legacy_priority_binary_exhaustive']+=1
        if (status,out)!=(m_status,expected):
            failures.append((old,word, m_status,expected,status,out,steps,head))
    # Warning only: this committed VERSION 2 example has just two rules,
    # while examples/priority.markov now contains three.
    current_rules=[('00','1',False),('11','0',True),('01','1011',True)]
    missing_rule_differences=0
    for word in words('01',8):
        _, expected, _ = markov_run(current_rules, word)
        _, actual, _, _ = simulate(d, t, word)
        if expected != actual:
            missing_rule_differences += 1
    print('WARNING: stored v2 example mismatches current 3-rule .markov source on',
          missing_rule_differences, 'of 511 inputs; regenerate this artifact with v1.5 compiler')
    print('tests',dict(tests))
    print('failures',len(failures))
    if failures:
        for f in failures[:15]:print('FAIL:',f)
    print('duration',round(time.monotonic()-begin,2),'s')
    return tests,failures

if __name__=='__main__':
    _,errs=main()
    raise SystemExit(1 if errs else 0)
