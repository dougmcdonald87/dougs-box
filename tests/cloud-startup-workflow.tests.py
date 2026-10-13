"""Evaluate the actual manual workflow's persistence execution graph and env scope."""
import ast,pathlib,re,unittest,yaml

workflow=yaml.safe_load((pathlib.Path(__file__).resolve().parents[1]/'.github/workflows/devbox.yml').read_text())

def evaluate(value,context):
    if not isinstance(value,str) or not value.strip().startswith('${{'):return value
    expression=value.strip()[3:-2].strip().replace('&&',' and ').replace('||',' or ')
    def visit(node):
        if isinstance(node,ast.Constant):return node.value
        if isinstance(node,ast.Name):return context[node.id]
        if isinstance(node,ast.Attribute):return visit(node.value).get(node.attr,'')
        if isinstance(node,ast.BoolOp):
            result=visit(node.values[0])
            for child in node.values[1:]:
                if isinstance(node.op,ast.And) and not result:return result
                if isinstance(node.op,ast.Or) and result:return result
                result=visit(child)
            return result
        if isinstance(node,ast.Compare) and len(node.ops)==1:
            left,right=visit(node.left),visit(node.comparators[0])
            if isinstance(node.ops[0],ast.Eq):return left==right
            if isinstance(node.ops[0],ast.NotEq):return left!=right
        if isinstance(node,ast.Call) and isinstance(node.func,ast.Name) and node.func.id=='success' and not node.args:return True
        raise AssertionError('Unsupported workflow expression: '+expression)
    return visit(ast.parse(expression,mode='eval').body)

class WorkflowTests(unittest.TestCase):
    def graph(self,selection):
        trigger=workflow.get('on',workflow.get(True,{}))
        declaration=trigger['workflow_dispatch']['inputs'].get('persistence_backend')
        self.assertIsNotNone(declaration,'manual cloud backend selection unavailable')
        self.assertEqual(declaration['default'],'home','normal launch must retain existing backend')
        self.assertIn(selection,declaration['options'])
        context={'inputs':{'operation':'start','persistence_backend':selection},'github':{'token':'JOB_TOKEN'},
                 'secrets':{'RESTIC_PASSWORD':'BACKUP_KEY','DEVBOX_STORAGE_PASSWORD':'HOME_KEY'},'env':{},'steps':{'terminal':{'outcome':'success'}}}
        job=workflow['jobs']['devbox'];env={}
        for source in (workflow.get('env',{}),job.get('env',{})):
            for key,value in source.items():env[key]=evaluate(value,context)
        context['env']=env
        graph=[]
        for step in job['steps']:
            match=re.search(r'scripts/([a-z-]+\.ps1)',step.get('run',''))
            if not match or match[1] not in ('bootstrap.ps1','connect-persistence.ps1','restore-state.ps1','migrate-cloud-persistence.ps1','save-state.ps1','session-manager.ps1'):continue
            condition=step.get('if')
            if condition and not evaluate(condition,context):continue
            effective={**env,**{key:evaluate(value,context) for key,value in step.get('env',{}).items()}}
            name=match[1]
            if name=='bootstrap.ps1':
                self.assertIn('-CloudCandidate:',step['run'],'selected cloud must request candidate workspace')
                self.assertEqual(effective['DEVBOX_PERSISTENCE_SELECTION'],selection)
            if name in ('connect-persistence.ps1','restore-state.ps1','migrate-cloud-persistence.ps1','save-state.ps1','session-manager.ps1'):
                graph.append((name,effective.get('DEVBOX_PERSISTENCE_BACKEND','home'),effective.get('GH_TOKEN')))
            if name=='migrate-cloud-persistence.ps1':
                # Successful native migration writes this actual GITHUB_ENV output;
                # its implementation and failure path run in independent Windows CI.
                env['DEVBOX_PERSISTENCE_BACKEND']='github-release'
        return graph
    def test_default_home_graph_remains_existing_restore_and_save(self):
        graph=self.graph('home')
        self.assertEqual([(name,backend) for name,backend,_ in graph],[
            ('connect-persistence.ps1','home'),('restore-state.ps1','home'),('save-state.ps1','home'),('session-manager.ps1','home')])
    def test_cloud_graph_carries_job_token_through_periodic_saves(self):
        graph=self.graph('github-release')
        self.assertEqual(graph,[('connect-persistence.ps1','github-release','JOB_TOKEN'),('restore-state.ps1','github-release','JOB_TOKEN'),
                                ('save-state.ps1','github-release','JOB_TOKEN'),('session-manager.ps1','github-release','JOB_TOKEN')])
        self.assertEqual(workflow['jobs']['devbox']['permissions']['contents'],'write')
        self.assertEqual(workflow['permissions']['contents'],'read')
    def test_migration_uses_source_once_then_cloud_save_and_session(self):
        graph=self.graph('migrate-to-github')
        self.assertEqual(graph,[('connect-persistence.ps1','home','JOB_TOKEN'),('migrate-cloud-persistence.ps1','home','JOB_TOKEN'),
                                ('save-state.ps1','github-release','JOB_TOKEN'),('session-manager.ps1','github-release','JOB_TOKEN')])
    def test_operational_workflow_remains_manual_and_never_cancels_session(self):
        trigger=workflow.get('on',workflow.get(True,{}))
        self.assertEqual(set(trigger),{'workflow_dispatch'})
        self.assertIs(workflow['jobs']['devbox']['concurrency']['cancel-in-progress'],False)
        self.assertNotIn('permissions',workflow['jobs']['terminal-relay'])

if __name__=='__main__':unittest.main()
