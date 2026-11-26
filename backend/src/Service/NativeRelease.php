<?php

declare(strict_types=1);

namespace App\Service;

use App\Entity\Api\Admin\UpdateDetails;
use App\Environment;
use Dotenv\Dotenv;
use GuzzleHttp\RequestOptions;
use RuntimeException;
use Throwable;

/**
 * Release information and update checks for native (non-Docker) AzuraCast-LXC installations.
 *
 * The native installer writes /etc/azuracast/release.env with the installed release and channel.
 * Releases are published on GitHub: the "main" channel (production) gets normal releases (vX.Y.Z),
 * the "test" channel gets prereleases (vX.Y.Z-test.N).
 */
final class NativeRelease
{
    public const string DEFAULT_REPOSITORY = 'rhisijmuiden/azuracast-lxc';

    public const string CHANNEL_MAIN = 'main';
    public const string CHANNEL_TEST = 'test';

    /** Directory watched by the azuracast-updater systemd path unit. */
    public const string UPDATER_DIR = '/var/azuracast/updater';

    private ?array $releaseInfo = null;

    public function __construct(
        private readonly GuzzleFactory $guzzleFactory,
    ) {
    }

    /**
     * @return array{version: string, tag: string, channel: string, repository: string}
     */
    public function getReleaseInfo(): array
    {
        if (null === $this->releaseInfo) {
            $raw = [];
            if (is_file(Environment::NATIVE_RELEASE_FILE)) {
                try {
                    $raw = Dotenv::parse((string)file_get_contents(Environment::NATIVE_RELEASE_FILE));
                } catch (Throwable) {
                    $raw = [];
                }
            }

            $channel = ($raw['NATIVE_CHANNEL'] ?? self::CHANNEL_MAIN) === self::CHANNEL_TEST
                ? self::CHANNEL_TEST
                : self::CHANNEL_MAIN;

            $this->releaseInfo = [
                'version' => (string)($raw['NATIVE_VERSION'] ?? '0.0.0'),
                'tag' => (string)($raw['NATIVE_TAG'] ?? ''),
                'channel' => $channel,
                'repository' => (string)($raw['NATIVE_REPOSITORY'] ?? self::DEFAULT_REPOSITORY),
            ];
        }

        return $this->releaseInfo;
    }

    public function getVersion(): string
    {
        return $this->getReleaseInfo()['version'];
    }

    public function getChannel(): string
    {
        return $this->getReleaseInfo()['channel'];
    }

    public function getChannelLabel(): string
    {
        return (self::CHANNEL_TEST === $this->getChannel())
            ? __('Test channel')
            : __('Production channel');
    }

    /**
     * Ask GitHub which releases exist and compare them with the installed one.
     */
    public function checkForUpdates(): UpdateDetails
    {
        $info = $this->getReleaseInfo();

        $client = $this->guzzleFactory->buildClient();
        $response = $client->request(
            'GET',
            'https://api.github.com/repos/' . $info['repository'] . '/releases',
            [
                RequestOptions::HTTP_ERRORS => true,
                RequestOptions::TIMEOUT => 15,
                RequestOptions::QUERY => ['per_page' => 50],
                RequestOptions::HEADERS => [
                    'Accept' => 'application/vnd.github+json',
                    'User-Agent' => 'AzuraCast-LXC updater',
                ],
            ]
        );

        $releases = json_decode($response->getBody()->getContents(), true, 512, JSON_THROW_ON_ERROR);
        if (!is_array($releases)) {
            throw new RuntimeException('GitHub did not return release information.');
        }

        $isTest = self::CHANNEL_TEST === $info['channel'];
        $current = $info['version'];

        $candidates = [];
        foreach ($releases as $release) {
            if (!is_array($release) || !empty($release['draft'])) {
                continue;
            }

            $isPrerelease = !empty($release['prerelease']);
            if ($isPrerelease !== $isTest) {
                continue;
            }

            $version = ltrim((string)($release['tag_name'] ?? ''), 'v');
            if ('' !== $version) {
                $candidates[] = $version;
            }
        }

        usort($candidates, static fn(string $a, string $b) => version_compare($b, $a));

        $latest = $candidates[0] ?? $current;
        $newer = array_filter(
            $candidates,
            static fn(string $v) => version_compare($v, $current, '>')
        );

        return new UpdateDetails(
            current_release: $current,
            latest_release: $latest,
            needs_rolling_update: $isTest && count($newer) > 0,
            needs_release_update: !$isTest && count($newer) > 0,
            rolling_updates_available: $isTest ? count($newer) : 0,
            can_switch_to_stable: true
        );
    }

    public function isUpdaterAvailable(): bool
    {
        return is_dir(self::UPDATER_DIR) && is_writable(self::UPDATER_DIR);
    }

    /**
     * Ask the root-owned azuracast-updater service (systemd path unit) to run an update.
     */
    public function requestUpdate(): void
    {
        if (!$this->isUpdaterAvailable()) {
            throw new RuntimeException(
                __('The native updater service is not available on this installation.')
            );
        }

        $written = file_put_contents(
            self::UPDATER_DIR . '/request',
            json_encode(['requested_at' => time(), 'action' => 'update'], JSON_THROW_ON_ERROR)
        );

        if (false === $written) {
            throw new RuntimeException(__('Could not start the update.'));
        }
    }
}
