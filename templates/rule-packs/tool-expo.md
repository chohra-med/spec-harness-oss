# Tool pack: Expo

<!-- rule-layer: tool -->
<!-- pack: tool-expo -->
<!-- applies: expo >=50 -->

- **EXPO-01** Add or update an Expo-managed library with `npx expo install` so its version matches the project's SDK. (source: Expo documentation, Using libraries, https://docs.expo.dev/workflow/using-libraries/)
- **EXPO-02** Check a library's platform compatibility on its Expo reference page before adopting it. (source: Expo documentation, Using libraries, https://docs.expo.dev/workflow/using-libraries/)
- **EXPO-03** Never put a secret in an `EXPO_PUBLIC_` variable, because its value ships in the app bundle in plain text. (source: Expo documentation, Environment variables, https://docs.expo.dev/guides/environment-variables/)
- **EXPO-04** When the React Compiler experiment is on, opt a component or file out with the `'use no memo'` directive only when the compiler breaks it, never by default. (source: Expo documentation, React Compiler, https://docs.expo.dev/guides/react-compiler/)
- **EXPO-05** Render remote and large images with `expo-image`, keep its `allowDownscaling` on, and give an image inside a recycled list a `recyclingKey`. (source: Expo documentation, Image, https://docs.expo.dev/versions/latest/sdk/image/)
- **EXPO-06** Wrap development-only code in `__DEV__` checks so it is removed from production bundles. (source: Expo blog, Expo application performance best practices, https://expo.dev/blog/best-practices-for-reducing-lag-in-expo-apps)
- **EXPO-07** Use `import` and `export` for code modules, not `require`, so Expo CLI can tree-shake them; `require` stays fine for assets such as images. (source: Expo blog, Expo application performance best practices, https://expo.dev/blog/best-practices-for-reducing-lag-in-expo-apps)
