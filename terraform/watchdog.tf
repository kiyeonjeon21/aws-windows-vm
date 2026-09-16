# A backstop for the in-guest idle watchdog.
#
# The watchdog inside Windows is the one that should normally act: it knows
# about SSH sessions, so it will not stop a box you are reading code on. But it
# is a scheduled task, and a scheduled task can stop recurring while still
# reporting healthy. That happened, and the instance ran unattended for 37
# hours. Anything whose only job is to limit spending should not have a single
# point of failure inside the thing it is limiting.
#
# This alarm lives outside the guest and cannot be broken from inside it. The
# window is deliberately much longer than idle_shutdown_minutes so that under
# normal operation the in-guest watchdog always acts first and this never
# fires.

resource "aws_cloudwatch_metric_alarm" "idle_backstop" {
  count = var.idle_backstop_hours > 0 ? 1 : 0

  alarm_name  = "${var.name}-idle-backstop"
  alarm_description = "Stop ${var.name} when CPU stays low long enough that the in-guest watchdog has clearly failed."

  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic   = "Maximum"

  dimensions = {
    InstanceId = aws_instance.this.id
  }

  comparison_operator = "LessThanThreshold"
  threshold           = var.idle_backstop_cpu_threshold
  period              = 300
  evaluation_periods  = var.idle_backstop_hours * 12

  # A stopped instance reports no data. Treating that as breaching would put
  # the alarm permanently in ALARM while stopped, so it has to be ignored.
  treat_missing_data = "missing"

  alarm_actions = ["arn:${data.aws_partition.current.partition}:automate:${var.region}:ec2:stop"]

  tags = { Name = "${var.name}-idle-backstop" }
}
