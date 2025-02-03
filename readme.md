update chg:

get change details: https://SN_URL/api/sn_chg_rest/v1/change/${{ env.CHG_SYS_ID }}

data: (key/value pairs)

  work_notes: notes to update
  user_id: user_id update as
  state: ticket state to update to
  close_code: ticket closure code
  close_notes: ticket closure notes

work_notes and close_notes:
  when adding a hyperlink, the `<a href="url">link text</a>` must be wrapped in `[code]...[/code]` in order for servicenow to display/embed it properly. probably just include this in the readme

no data inputs will be required. should dynamically build the data payload from input key (corresponding key name) and value.

should NOT pass anything as data that isn't supplied a value - unsure of outcome of passing `{"state": ""}` - does it cause a HTTP 4xx error? silently fail and continue? put the ticket in an invalid state?