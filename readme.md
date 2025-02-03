get chg:

get change details: https://SN_URL/api/now/table/change_request?sysparm_query=number%3D${{ github.event.inputs.ticket }}

get CHG sys_id: pipe into: ` | jq -r '.result[0].sys_id')`