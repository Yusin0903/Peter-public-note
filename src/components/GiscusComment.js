import React from 'react';
import Giscus from '@giscus/react';
import { useColorMode } from '@docusaurus/theme-common';

export default function GiscusComment() {
  const { colorMode } = useColorMode();

  return (
    <div style={{ marginTop: '2rem' }}>
      <Giscus
        repo="Yusin0903/Peter-public-note"
        repoId="R_kgDOSEgDwg"
        category="General"
        categoryId="DIC_kwDOSEgDws4C8Sw2"
        mapping="pathname"
        strict="0"
        reactionsEnabled="1"
        emitMetadata="0"
        inputPosition="bottom"
        theme={colorMode === 'dark' ? 'dark' : 'light'}
        lang="zh-TW"
        crossOrigin="anonymous"
      />
    </div>
  );
}
