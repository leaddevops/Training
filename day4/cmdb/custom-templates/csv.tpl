<%

import sys
import csv
import logging

log = logging.getLogger(__name__)

cols = [
  {"title": "Name",       "id": "name",       "visible": True, "field": lambda h: h.get('name', '')},
  {"title": "IP",         "id": "ip",         "visible": True, "field": lambda h: host['ansible_facts'].get('ansible_default_ipv4', {}).get('address', '')},
  {"title": "Cont_Count", "id": "ContC",      "visible": True, "field": lambda h: host['ansible_facts'].get('ansible_local', {}).get('contFacts', {}).get('Placement', {}).get('cont_count', '')},
  {"title": "VMType",     "id": "vmt",        "visible": True, "field": lambda h: host['ansible_facts'].get('ansible_local', {}).get('contFacts', {}).get('Placement', {}).get('vmtype', '')},
  {"title": "Mem",        "id": "mem",        "visible": True, "field": lambda h: '%0.0fg' % (int(host['ansible_facts'].get('ansible_memtotal_mb', 0)) / 1000.0)},
  {"title": "vCPUs",      "id": "cpus",       "visible": True, "field": lambda h: host['ansible_facts'].get('ansible_local', {}).get('contFacts', {}).get('Placement', {}).get('vcpus', '')},
  {"title": "UPTIME",     "id": "upt",        "visible": True, "field": lambda h: host['ansible_facts'].get('ansible_local', {}).get('contFacts', {}).get('Placement', {}).get('uptime', '')},
  {"title": "OS",         "id": "os",         "visible": True, "field": lambda h: h['ansible_facts'].get('ansible_distribution', '') + ' ' + h['ansible_facts'].get('ansible_distribution_version', '')},
  {"title": "Arch",       "id": "arch",       "visible": True, "field": lambda h: host['ansible_facts'].get('ansible_architecture', 'Unk') + '/' + host['ansible_facts'].get('ansible_userspace_architecture', 'Unk')},
]

# Enable columns specified with '--columns'
if columns is not None:
  for col in cols:
    if col["id"] in columns:
      col["visible"] = True
    else:
      col["visible"] = False

def get_cols():
  return [col for col in cols if col['visible'] is True]

fieldnames = []
for col in get_cols():
  fieldnames.append(col['title'])

writer = csv.writer(sys.stdout, delimiter=',', quotechar='"', quoting=csv.QUOTE_ALL)
writer.writerow(fieldnames)
for hostname, host in hosts.items():
  if 'ansible_facts' not in host:
    log.warning(u'{0}: No info collected.'.format(hostname))
  else:
    out_cols = []
    for col in get_cols():
      out_cols.append(col['field'](host))
    writer.writerow(out_cols)
%>
