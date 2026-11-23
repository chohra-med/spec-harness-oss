# Tool pack: React Native

<!-- rule-layer: tool -->
<!-- pack: tool-react-native -->
<!-- applies: react-native >=0.70 -->

- **RN-01** Give every list a `keyExtractor` that returns a stable key for each item. (source: React Native documentation, Optimizing FlatList configuration, https://reactnative.dev/docs/optimizing-flatlist-configuration)
- **RN-02** Keep list item components light and wrap them in `React.memo` when their props are stable. (source: React Native documentation, Optimizing FlatList configuration, https://reactnative.dev/docs/optimizing-flatlist-configuration)
- **RN-03** Provide `getItemLayout` when every row of a list has the same fixed height. (source: React Native documentation, Optimizing FlatList configuration, https://reactnative.dev/docs/optimizing-flatlist-configuration)
- **RN-04** Set an `accessibilityLabel` on every touchable element whose purpose its text does not already state. (source: React Native documentation, Accessibility, https://reactnative.dev/docs/accessibility)
- **RN-05** Judge JavaScript performance on a release build, because development mode runs slower. (source: React Native documentation, Performance overview, https://reactnative.dev/docs/0.77/performance)
- **RN-06** Render a list that can grow long with a virtualized list such as FlatList, FlashList or Legend List, not a ScrollView that maps every item. (source: Callstack, React Native best practices skill, js-lists-flatlist-flashlist, https://github.com/callstackincubator/agent-skills/blob/main/skills/react-native-best-practices/SKILL.md)
- **RN-07** Keep long synchronous work off the JavaScript thread, and run gesture-driven animations as `react-native-reanimated` worklets on the UI thread. (source: Expo blog, Expo application performance best practices, https://expo.dev/blog/best-practices-for-reducing-lag-in-expo-apps)
- **RN-08** Handle gestures with `react-native-gesture-handler` and never with `PanResponder`. (source: Expo blog, Expo application performance best practices, https://expo.dev/blog/best-practices-for-reducing-lag-in-expo-apps)
- **RN-09** When typing in a controlled `TextInput` lags, make it an uncontrolled input instead of adding memoization around it. (source: Callstack, React Native best practices skill, js-uncontrolled-components, https://github.com/callstackincubator/agent-skills/blob/main/skills/react-native-best-practices/SKILL.md)
- **RN-10** Stop every listener, timer and subscription that a component or effect starts in its cleanup, so nothing keeps running or fires after the screen unmounts. (source: React documentation, Synchronizing with Effects, https://react.dev/learn/synchronizing-with-effects)
- **RN-11** Import a module from its own file instead of through a barrel index file, so the bundler can leave unused code out. (source: Expo blog, Expo application performance best practices, https://expo.dev/blog/best-practices-for-reducing-lag-in-expo-apps)
