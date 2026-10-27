import json
import boto3
import os

# ECS client
ecs = boto3.client('ecs', region_name='us-east-1')

CLUSTER_NAME = os.environ.get('ECS_CLUSTER', 'pr4-cluster')

def lambda_handler(event, context):
    """
    Lambda function to invoke ECS API.
    
    Supported actions via event['action']:
      - list_tasks     : List all running task ARNs in the cluster
      - describe_tasks : Get full details of all running tasks
      - stop_task      : Stop a specific task (requires event['task_arn'])
    """
    action = event.get('action', 'list_tasks')
    
    print(f"[PR4 Lambda] Action received: {action}")
    print(f"[PR4 Lambda] Cluster: {CLUSTER_NAME}")

    # -------------------------------------------------------
    # Action: list_tasks
    # -------------------------------------------------------
    if action == 'list_tasks':
        response = ecs.list_tasks(
            cluster=CLUSTER_NAME,
            desiredStatus='RUNNING'
        )
        task_arns = response.get('taskArns', [])
        print(f"[PR4 Lambda] Found {len(task_arns)} running task(s)")
        return {
            'statusCode': 200,
            'action': 'list_tasks',
            'cluster': CLUSTER_NAME,
            'taskCount': len(task_arns),
            'taskArns': task_arns
        }

    # -------------------------------------------------------
    # Action: describe_tasks
    # -------------------------------------------------------
    elif action == 'describe_tasks':
        # First get task ARNs
        list_resp = ecs.list_tasks(
            cluster=CLUSTER_NAME,
            desiredStatus='RUNNING'
        )
        task_arns = list_resp.get('taskArns', [])

        if not task_arns:
            return {
                'statusCode': 200,
                'action': 'describe_tasks',
                'cluster': CLUSTER_NAME,
                'message': 'No running tasks found',
                'tasks': []
            }

        # Describe tasks
        desc_resp = ecs.describe_tasks(
            cluster=CLUSTER_NAME,
            tasks=task_arns
        )

        tasks_summary = []
        for task in desc_resp.get('tasks', []):
            # Extract public IP if available
            public_ip = None
            attachments = task.get('attachments', [])
            for attachment in attachments:
                for detail in attachment.get('details', []):
                    if detail.get('name') == 'networkInterfaceId':
                        # Get ENI details to find public IP
                        try:
                            ec2 = boto3.client('ec2', region_name='us-east-1')
                            eni = ec2.describe_network_interfaces(
                                NetworkInterfaceIds=[detail['value']]
                            )
                            assoc = eni['NetworkInterfaces'][0].get('Association', {})
                            public_ip = assoc.get('PublicIp')
                        except Exception:
                            pass

            containers = [
                {
                    'name': c['name'],
                    'status': c['lastStatus'],
                    'image': c.get('image', 'N/A')
                }
                for c in task.get('containers', [])
            ]

            tasks_summary.append({
                'taskArn': task['taskArn'],
                'taskDefinitionArn': task.get('taskDefinitionArn'),
                'lastStatus': task['lastStatus'],
                'desiredStatus': task['desiredStatus'],
                'cpu': task.get('cpu'),
                'memory': task.get('memory'),
                'publicIp': public_ip,
                'startedAt': str(task.get('startedAt', 'N/A')),
                'containers': containers
            })

        print(f"[PR4 Lambda] Described {len(tasks_summary)} task(s)")
        return {
            'statusCode': 200,
            'action': 'describe_tasks',
            'cluster': CLUSTER_NAME,
            'taskCount': len(tasks_summary),
            'tasks': tasks_summary
        }

    # -------------------------------------------------------
    # Action: stop_task
    # -------------------------------------------------------
    elif action == 'stop_task':
        task_arn = event.get('task_arn')
        if not task_arn:
            return {
                'statusCode': 400,
                'error': 'task_arn is required for stop_task action'
            }

        response = ecs.stop_task(
            cluster=CLUSTER_NAME,
            task=task_arn,
            reason='Stopped by Lambda pr4-ecs-invoker'
        )
        print(f"[PR4 Lambda] Stopped task: {task_arn}")
        return {
            'statusCode': 200,
            'action': 'stop_task',
            'cluster': CLUSTER_NAME,
            'stoppedTaskArn': task_arn,
            'lastStatus': response['task']['lastStatus']
        }

    # -------------------------------------------------------
    # Unknown action
    # -------------------------------------------------------
    else:
        return {
            'statusCode': 400,
            'error': f"Unknown action: '{action}'. Valid actions: list_tasks, describe_tasks, stop_task"
        }
