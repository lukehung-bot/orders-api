# ---------------------------------------------------------------------------
# 告警：一個 alarm 同時涵蓋兩種狀況（metric math）
#   (1) ALB 回 5xx：target 5xx（程式錯誤）+ ELB 5xx（例如 502/503 沒有健康 target）
#   (2) 服務掛掉：Target Group 健康主機數 < 1
# 連續 3 分鐘內有 2 分鐘成立才觸發，避免單一尖峰誤報；恢復時也會通知（OK action）
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "service_unhealthy" {
  alarm_name          = "${var.project}-5xx-or-down"
  alarm_description   = "ALB 5xx >= ${var.alarm_5xx_threshold}/min OR healthy targets < 1"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching" # 完全沒有資料 = 視為異常（服務可能根本不存在）
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "e1"
    label       = "unhealthy (1 = alarm)"
    expression  = "IF((FILL(m1,0) + FILL(m2,0)) >= ${var.alarm_5xx_threshold} OR FILL(m3,0) < 1, 1, 0)"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = aws_lb.main.arn_suffix }
    }
  }

  metric_query {
    id = "m2"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = aws_lb.main.arn_suffix }
    }
  }

  metric_query {
    id = "m3"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HealthyHostCount"
      period      = 60
      stat        = "Minimum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
        TargetGroup  = aws_lb_target_group.app.arn_suffix
      }
    }
  }
}
