/** Compact shell for DashLink. Move existing controls so their behavior stays shared. */
export function configureDesktopViewer(): void {
  if (new URL(location.href).searchParams.get('desktop') !== '1') return;
  document.body.classList.add('desktop');
  document.title = 'DashLink · CarPlay';
  const app = document.getElementById('app')!;
  const bar = document.createElement('footer');
  bar.className = 'desktop-controls';
  bar.setAttribute('aria-label', 'CarPlay controls');
  const navigation = document.createElement('div');
  navigation.className = 'desktop-navigation';
  for (const id of ['btn-back', 'btn-home', 'btn-siri']) navigation.append(document.getElementById(id)!);
  bar.append(navigation, document.querySelector('.media-controls')!, document.querySelector('.quick-volume')!);

  const more = document.createElement('button');
  more.className = 'desktop-more';
  more.textContent = 'More';
  more.setAttribute('aria-haspopup', 'dialog');
  more.setAttribute('aria-controls', 'desktop-options');
  const options = document.createElement('div');
  options.id = 'desktop-options';
  options.popover = 'auto';
  options.setAttribute('role', 'dialog');
  options.setAttribute('aria-label', 'Viewer options');
  more.popoverTargetElement = options;
  for (const id of ['btn-display', 'btn-audio', 'btn-night', 'btn-fullscreen', 'btn-keyframe', 'btn-help', 'btn-answer', 'btn-call-mute']) {
    const button = document.getElementById(id)!;
    if (!button.querySelector('span')) {
      const label = document.createElement('span');
      label.textContent = button.getAttribute('aria-label') ?? button.getAttribute('title');
      button.append(label);
    }
    button.addEventListener('click', () => options.hidePopover());
    options.append(button);
  }
  const stats = document.createElement('p');
  stats.className = 'desktop-stats';
  stats.append(document.getElementById('stream-info')!);
  options.append(stats);
  bar.append(more);
  app.append(bar, document.getElementById('mic-status')!);
  document.body.append(options);

  document.getElementById('audio-title')!.textContent = 'Sound';
  document.querySelector('#audio-panel .panel-hint')!.textContent = 'Volume is kept for this session.';
  document.querySelector('#audio-panel .panel-tip p')!.textContent = 'Siri and calls can use your Mac’s microphone. Allow access only when you want to talk back.';
  document.querySelectorAll('#audio-panel h3')[1].textContent = 'Music and voice';
  document.getElementById('help-title')!.textContent = 'CarPlay controls';
  const guide = document.querySelector('.connection-steps')!;
  const instructions = [
    ['Connect in DashLink', 'Choose your iPhone and enter the Wi-Fi details in the connection screen. Both devices must use the same network.'],
    ['Allow CarPlay', 'Accept the prompt on your iPhone. If a PIN is requested, enter 3939.'],
    ['Use the screen', 'Click the live CarPlay screen, or use the controls below. Sound starts automatically when supported.'],
  ];
  guide.querySelectorAll('li').forEach((row, index) => {
    row.querySelector('strong')!.textContent = instructions[index][0];
    row.querySelector('p')!.textContent = instructions[index][1];
  });
}
