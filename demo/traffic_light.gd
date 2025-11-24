extends TrafficLight

func _get_next_light(p_current_light: TrafficLightType) -> TrafficLightType:
	if p_current_light == TrafficLightType.TRAFFIC_LIGHT_STOP:
		return TrafficLightType.TRAFFIC_LIGHT_GO
	elif p_current_light == TrafficLightType.TRAFFIC_LIGHT_GO:
		return TrafficLightType.TRAFFIC_LIGHT_CAUTION
	else:
		return TrafficLightType.TRAFFIC_LIGHT_STOP