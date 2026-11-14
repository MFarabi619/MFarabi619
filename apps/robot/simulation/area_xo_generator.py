#!/usr/bin/env python3

# Copyright 2026 Mumtahin Farabi
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


import functools
import hashlib
import json
import math
import os
import subprocess
import urllib.parse

SIMULATION_DIRECTORY = os.path.dirname(os.path.abspath(__file__))
DOWNLOAD_DIRECTORY = os.path.join(SIMULATION_DIRECTORY, 'downloads', 'area_xo')
WCS_CACHE_DIRECTORY = os.path.join(DOWNLOAD_DIRECTORY, 'wcs')
PROJ_CACHE_DIRECTORY = os.path.join(SIMULATION_DIRECTORY, 'downloads', 'proj')
GDAL_ENVIRONMENT = {
    'PROJ_NETWORK': 'ON',
    'PROJ_USER_WRITABLE_DIRECTORY': PROJ_CACHE_DIRECTORY,
    'GDAL_HTTP_MAX_RETRY': '5',
    'GDAL_HTTP_RETRY_DELAY': '30',
}
TERRAIN_DIRECTORY = os.path.join(SIMULATION_DIRECTORY, 'models', 'area_xo', 'terrain')
WORLD_PATH = os.path.join(SIMULATION_DIRECTORY, 'worlds', 'area_xo.sdf')
HEIGHTMAP_PATH = os.path.join(TERRAIN_DIRECTORY, 'ground.tif')
TEXTURE_PATH = os.path.join(TERRAIN_DIRECTORY, 'imagery.jpg')
NORMAL_MAP_PATH = os.path.join(TERRAIN_DIRECTORY, 'flat_normal.png')

ORIGIN_LATITUDE_DEGREES = 45.3188036
ORIGIN_LONGITUDE_DEGREES = -75.7563699
COORDINATE_EPOCH_DECIMAL_YEAR = 2026.9

HEIGHTMAP_INTERVALS = 8192
HEIGHTMAP_RESOLUTION_METERS = 0.32
HEIGHTMAP_SAMPLE_MARGIN_METERS = HEIGHTMAP_RESOLUTION_METERS / 2.0
TERRAIN_SIZE_METERS = HEIGHTMAP_INTERVALS * HEIGHTMAP_RESOLUTION_METERS
TERRAIN_CENTER_EAST_METERS = 0.0
TERRAIN_CENTER_NORTH_METERS = 0.0
TEXTURE_PIXELS = 16384
DOWNLOAD_MARGIN_METERS = 100.0
ELEVATION_RESOLUTION_METERS = 0.5
IMAGERY_RESOLUTION_METERS = 0.16

WGS84_CRS = 'EPSG:4326'
WEB_MERCATOR_CRS = 'EPSG:3857'
NAD83_CSRS_UTM_18N_EPSG_CODE = '2959'
NAD83_CSRS_UTM_18N_CRS = f'EPSG:{NAD83_CSRS_UTM_18N_EPSG_CODE}'
NAD83_CSRS_V7_UTM_18N_CRS = 'EPSG:22718'
NAD83_CSRS_V7_UTM_18N_CGVD2013_CRS = 'EPSG:22718+6647'
LOCAL_CRS = f"""PROJCRS["Area X.O",
    BASEGEOGCRS["ITRF2020",
        DYNAMIC[FRAMEEPOCH[2015]],
        DATUM["International Terrestrial Reference Frame 2020",
            ELLIPSOID["GRS 1980",6378137,298.257222101,LENGTHUNIT["metre",1]]],
        PRIMEM["Greenwich",0,ANGLEUNIT["degree",0.0174532925199433]],
        ID["EPSG",9989]],
    CONVERSION["Area X.O transverse Mercator",
        METHOD["Transverse Mercator",ID["EPSG",9807]],
        PARAMETER["Latitude of natural origin",{ORIGIN_LATITUDE_DEGREES},
            ANGLEUNIT["degree",0.0174532925199433]],
        PARAMETER["Longitude of natural origin",{ORIGIN_LONGITUDE_DEGREES},
            ANGLEUNIT["degree",0.0174532925199433]],
        PARAMETER["Scale factor at natural origin",1,SCALEUNIT["unity",1]],
        PARAMETER["False easting",0,LENGTHUNIT["metre",1]],
        PARAMETER["False northing",0,LENGTHUNIT["metre",1]]],
    CS[Cartesian,3],
        AXIS["easting (E)",east,LENGTHUNIT["metre",1]],
        AXIS["northing (N)",north,LENGTHUNIT["metre",1]],
        AXIS["ellipsoidal height (h)",up,LENGTHUNIT["metre",1]]]"""

ONTARIO_SERVICES_URL = 'https://ws.geoservices.lrc.gov.on.ca/arcgis5/services'
WCS_VERSION = '2.0.1'
WMS_VERSION = '1.1.1'
GROUND_COVERAGE = 'Ontario_DTM_LidarDerived'
SURFACE_COVERAGE = 'Ontario_DSM_LidarDerived'
IMAGERY_LAYER = 'GEO_Imagery_Data_Service_2023to2027:DRAPE_2024'
IMAGERY_WMS_URL = (f'{ONTARIO_SERVICES_URL}/AerialImagery/'
                   'GEO_Imagery_Data_Service_2023to2027/ImageServer/WMSServer?SERVICE=WMS')
FOOTPRINT_QUERY_URL = (
    'https://maps.ottawa.ca/arcgis/rest/services/TopographicMapping/MapServer/3/query')
SERVICE_BLOCK_PIXELS = 4096
SERVICE_TIMEOUT_SECONDS = 600
NODATA_VALUE = '3.4028234663852886e+38'
CACHE_DIGEST_HEX_CHARACTERS = 8

FOOTPRINT_ID_FIELD = 'footprint_id'
FOOTPRINT_SIMPLIFY_TOLERANCE_METERS = 0.2
FOOTPRINT_PRECISION_METERS = 0.001
ROOF_EDGE_INSET_METERS = 1.0
MIN_BUILDING_HEIGHT_METERS = 1.0
IMAGERY_JPEG_QUALITY = 95
TEXTURE_JPEG_QUALITY = 90
BUILDING_COLOR = '0.72 0.72 0.74 1'

SPAWN_LATITUDE_DEGREES = 45.3190278
SPAWN_LONGITUDE_DEGREES = -75.7559167
SPAWN_YAW_RADIANS = -2.529
SPAWN_CLEARANCE_METERS = 0.4


def run(*command, stdin=None):
    return subprocess.check_output(
        command, input=stdin, text=True, env={**os.environ, **GDAL_ENVIRONMENT})


def downloaded(file_name, cache_key, download):
    stem, extension = os.path.splitext(file_name)
    bounds_text = '_'.join(str(round(value)) for value in download_bounds())
    digest = hashlib.sha256(cache_key.encode()).hexdigest()[:CACHE_DIGEST_HEX_CHARACTERS]
    cached_path = os.path.join(DOWNLOAD_DIRECTORY, f'{stem}_{bounds_text}_{digest}{extension}')
    if not os.path.exists(cached_path):
        os.makedirs(DOWNLOAD_DIRECTORY, exist_ok=True)
        path_root, path_extension = os.path.splitext(cached_path)
        partial_path = f'{path_root}.partial{path_extension}'
        download(partial_path)
        os.replace(partial_path, cached_path)
    return cached_path


def transformed(source_crs, target_crs, points, *options):
    output = run('gdaltransform', '-s_srs', source_crs, '-t_srs', target_crs, *options,
                 '-output_xy', stdin=''.join(f'{x} {y}\n' for x, y in points))
    return [tuple(map(float, line.split())) for line in output.splitlines()]


def local_bounds(margin_meters=0.0):
    half_span = TERRAIN_SIZE_METERS / 2.0 + margin_meters
    return (TERRAIN_CENTER_EAST_METERS - half_span, TERRAIN_CENTER_NORTH_METERS - half_span,
            TERRAIN_CENTER_EAST_METERS + half_span, TERRAIN_CENTER_NORTH_METERS + half_span)


@functools.cache
def download_bounds():
    [(origin_easting, origin_northing)] = transformed(
        WGS84_CRS, NAD83_CSRS_UTM_18N_CRS, [(ORIGIN_LONGITUDE_DEGREES, ORIGIN_LATITUDE_DEGREES)])
    west, south, east, north = local_bounds(DOWNLOAD_MARGIN_METERS)
    return (origin_easting + west, origin_northing + south,
            origin_easting + east, origin_northing + north)


def wcs_connection_string(coverage_name):
    return (f'WCS:{ONTARIO_SERVICES_URL}/Elevation/{coverage_name}/ImageServer/WCSServer'
            f'?version={WCS_VERSION}&coverage={coverage_name}')


def elevation(coverage_name, file_name):
    cache_key = f'{wcs_connection_string(coverage_name)} {ELEVATION_RESOLUTION_METERS}'
    return downloaded(file_name, cache_key, lambda output_path: run(
        'gdalwarp', '-q',
        '-oo', f'CACHE={WCS_CACHE_DIRECTORY}',
        '-oo', f'BlockXSize={SERVICE_BLOCK_PIXELS}', '-oo', f'BlockYSize={SERVICE_BLOCK_PIXELS}',
        '-oo', f'Timeout={SERVICE_TIMEOUT_SECONDS}',
        '-s_srs', WEB_MERCATOR_CRS, '-t_srs', NAD83_CSRS_UTM_18N_CRS,
        '-te', *map(str, download_bounds()),
        '-tr', str(ELEVATION_RESOLUTION_METERS), str(ELEVATION_RESOLUTION_METERS),
        '-r', 'bilinear', '-srcnodata', NODATA_VALUE, '-dstnodata', NODATA_VALUE,
        '-co', 'COMPRESS=ZSTD', '-co', 'PREDICTOR=3', '-co', 'TILED=YES', '-co', 'BIGTIFF=YES',
        wcs_connection_string(coverage_name), output_path))


def imagery_service_description():
    west, south, east, north = download_bounds()
    (mercator_west, mercator_south), (mercator_east, mercator_north) = transformed(
        NAD83_CSRS_UTM_18N_CRS, WEB_MERCATOR_CRS, [(west, south), (east, north)])
    mercator_resolution_meters = IMAGERY_RESOLUTION_METERS / math.cos(
        math.radians(ORIGIN_LATITUDE_DEGREES))
    path = os.path.join(DOWNLOAD_DIRECTORY, f'{IMAGERY_LAYER.split(":")[1].lower()}.xml')
    with open(path, 'w') as description_file:
        description_file.write(f"""<GDAL_WMS>
  <Service name="WMS">
    <Version>{WMS_VERSION}</Version>
    <ServerUrl>{IMAGERY_WMS_URL}</ServerUrl>
    <Layers>{IMAGERY_LAYER}</Layers>
    <SRS>{WEB_MERCATOR_CRS}</SRS>
    <ImageFormat>image/png</ImageFormat>
    <Transparent>FALSE</Transparent>
    <BBoxOrder>xyXY</BBoxOrder>
  </Service>
  <DataWindow>
    <UpperLeftX>{mercator_west}</UpperLeftX>
    <UpperLeftY>{mercator_north}</UpperLeftY>
    <LowerRightX>{mercator_east}</LowerRightX>
    <LowerRightY>{mercator_south}</LowerRightY>
    <SizeX>{round((mercator_east - mercator_west) / mercator_resolution_meters)}</SizeX>
    <SizeY>{round((mercator_north - mercator_south) / mercator_resolution_meters)}</SizeY>
  </DataWindow>
  <BandsCount>3</BandsCount>
  <BlockSizeX>{SERVICE_BLOCK_PIXELS}</BlockSizeX>
  <BlockSizeY>{SERVICE_BLOCK_PIXELS}</BlockSizeY>
  <Timeout>{SERVICE_TIMEOUT_SECONDS}</Timeout>
</GDAL_WMS>
""")
    return path


def imagery():
    cache_key = f'{IMAGERY_WMS_URL} {IMAGERY_LAYER} {IMAGERY_RESOLUTION_METERS}'
    return downloaded('imagery.tif', cache_key, lambda output_path: run(
        'gdalwarp', '-q', '-s_srs', WEB_MERCATOR_CRS, '-t_srs', NAD83_CSRS_UTM_18N_CRS,
        '-te', *map(str, download_bounds()),
        '-tr', str(IMAGERY_RESOLUTION_METERS), str(IMAGERY_RESOLUTION_METERS),
        '-r', 'bilinear', '-co', 'COMPRESS=JPEG', '-co', f'JPEG_QUALITY={IMAGERY_JPEG_QUALITY}',
        '-co', 'PHOTOMETRIC=YCBCR', '-co', 'TILED=YES', '-co', 'BIGTIFF=YES',
        imagery_service_description(), output_path))


def footprints():
    west, south, east, north = download_bounds()
    query = urllib.parse.urlencode({
        'geometry': f'{west},{south},{east},{north}',
        'geometryType': 'esriGeometryEnvelope',
        'inSR': NAD83_CSRS_UTM_18N_EPSG_CODE,
        'spatialRel': 'esriSpatialRelContains',
        'outSR': NAD83_CSRS_UTM_18N_EPSG_CODE,
        'outFields': 'OBJECTID',
        'f': 'json',
    })
    request_url = f'{FOOTPRINT_QUERY_URL}?{query}'
    return downloaded('footprints.geojson', request_url, lambda output_path: run(
        'ogr2ogr', '-f', 'GeoJSON', output_path, f'ESRIJSON:{request_url}'))


def reproject_to_local(input_crs, *grid_options):
    return ['reproject', '--input-crs', input_crs, '--output-crs', LOCAL_CRS,
            '--to', f'DST_COORDINATE_EPOCH={COORDINATE_EPOCH_DECIMAL_YEAR}', *grid_options]


def heightmap_grid_options():
    return ['--bbox', ','.join(map(str, local_bounds(HEIGHTMAP_SAMPLE_MARGIN_METERS))),
            '--resolution', f'{HEIGHTMAP_RESOLUTION_METERS},{HEIGHTMAP_RESOLUTION_METERS}',
            '-r', 'bilinear']


def heightmap(ground_elevation_path):
    run('gdal', 'raster', 'pipeline', '--quiet', 'read', ground_elevation_path,
        '!', *reproject_to_local(NAD83_CSRS_V7_UTM_18N_CGVD2013_CRS, *heightmap_grid_options()),
        '!', 'fill-nodata', '!', 'write', '--overwrite', HEIGHTMAP_PATH)
    return HEIGHTMAP_PATH


def local_surface(surface_elevation_path):
    path = os.path.join(DOWNLOAD_DIRECTORY, 'surface_local.tif')
    run('gdal', 'raster', 'pipeline', '--quiet', 'read', surface_elevation_path,
        '!', *reproject_to_local(NAD83_CSRS_V7_UTM_18N_CGVD2013_CRS, *heightmap_grid_options()),
        '!', 'write', '--overwrite', path)
    return path


def texture(imagery_path):
    run('gdal', 'raster', 'pipeline', '--quiet', 'read', imagery_path,
        '!', *reproject_to_local(NAD83_CSRS_V7_UTM_18N_CRS,
                                 '--bbox', ','.join(map(str, local_bounds())),
                                 '--size', f'{TEXTURE_PIXELS},{TEXTURE_PIXELS}', '-r', 'cubic'),
        '!', 'write', '--overwrite', '--output-format', 'JPEG',
        '--creation-option', f'QUALITY={TEXTURE_JPEG_QUALITY}', TEXTURE_PATH)
    return TEXTURE_PATH


def local_footprints(footprints_path):
    exploded_path = os.path.join(DOWNLOAD_DIRECTORY, 'footprints_exploded.gpkg')
    numbered_path = os.path.join(DOWNLOAD_DIRECTORY, 'footprints_local.gpkg')
    run('ogr2ogr', '-overwrite', '-f', 'GPKG', '-nln', 'footprints',
        '-s_srs', NAD83_CSRS_V7_UTM_18N_CRS, '-t_srs', LOCAL_CRS,
        '-t_coord_epoch', str(COORDINATE_EPOCH_DECIMAL_YEAR),
        '-simplify', str(FOOTPRINT_SIMPLIFY_TOLERANCE_METERS), '-makevalid',
        '-explodecollections', '-nlt', 'POLYGON', exploded_path, footprints_path)
    reduced_precision_geometry = f'ST_ReducePrecision(geom, {FOOTPRINT_PRECISION_METERS})'
    run('ogr2ogr', '-overwrite', '-f', 'GPKG', '-nln', 'footprints', '-dialect', 'SQLite',
        '-sql', f'SELECT rowid * 1 AS {FOOTPRINT_ID_FIELD}, {reduced_precision_geometry} AS geom'
                f' FROM footprints WHERE NOT ST_IsEmpty({reduced_precision_geometry})',
        numbered_path, exploded_path)
    return numbered_path


def zonal_statistics(raster_path, zones, statistic, *options):
    output = run('gdal', 'pipeline', '--quiet', 'read', raster_path,
                 '!', 'zonal-stats', '--zones', *zones, '--stat', statistic,
                 '--include-field', FOOTPRINT_ID_FIELD, *options,
                 '!', 'write', '--output-format', 'GeoJSON', '/vsistdout/')
    return json.loads(output)['features']


def building_statistics(heightmap_path, surface_path, footprints_path):
    roof_zones = ['[', 'read', footprints_path,
                  '!', 'buffer', f'--distance=-{ROOF_EDGE_INSET_METERS}', ']']
    roof_height_by_footprint_id = {
        feature['properties'][FOOTPRINT_ID_FIELD]: feature['properties'].get('mean')
        for feature in zonal_statistics(surface_path, roof_zones, 'mean')}
    base_features = zonal_statistics(heightmap_path, [footprints_path], 'min', '--include-geom')
    return [(feature, roof_height_by_footprint_id.get(feature['properties'][FOOTPRINT_ID_FIELD]))
            for feature in base_features]


def height_at(raster_path, east, north):
    return float(run('gdallocationinfo', '-valonly', '-geoloc', raster_path,
                     str(east), str(north)))


def height_range(raster_path):
    band = json.loads(run('gdalinfo', '-json', '-mm', raster_path))['bands'][0]
    return band['computedMin'], band['computedMax']


def building(feature, roof_height, origin_height):
    geometry_type = feature['geometry']['type']
    if geometry_type != 'Polygon':
        raise ValueError(f'footprint {feature["properties"][FOOTPRINT_ID_FIELD]} is a '
                         f'{geometry_type}, expected a Polygon')
    base_height = feature['properties'].get('min')
    if (base_height is None or roof_height is None
            or roof_height - base_height < MIN_BUILDING_HEIGHT_METERS):
        return None
    return (feature['geometry']['coordinates'], base_height - origin_height,
            roof_height - base_height)


def flat_normal_map():
    run('gdal', 'raster', 'pipeline', '--quiet',
        'create', '--size', '1,1', '--band-count', '3',
        '--burn', '128', '--burn', '128', '--burn', '255',
        '!', 'write', '--overwrite', '--output-format', 'PNG', NORMAL_MAP_PATH)
    return NORMAL_MAP_PATH


def terrain_model(origin_height, heights):
    min_height, max_height = heights
    terrain_offset = (f'{TERRAIN_CENTER_EAST_METERS} {TERRAIN_CENTER_NORTH_METERS}'
                      f' {-origin_height:.3f}')
    shared_heightmap_elements = (
        f'<uri>model://area_xo/terrain/{os.path.basename(HEIGHTMAP_PATH)}</uri>\n'
        f'            <size>{TERRAIN_SIZE_METERS} {TERRAIN_SIZE_METERS}'
        f' {max_height - min_height:.3f}</size>')
    return f"""
    <model name="terrain">
      <static>true</static>
      <link name="link">
        <collision name="collision">
          <pose>{terrain_offset} 0 0 0</pose>
          <geometry><heightmap>
            {shared_heightmap_elements}
          </heightmap></geometry>
        </collision>
        <visual name="visual">
          <geometry><heightmap>
            {shared_heightmap_elements}
            <pos>{terrain_offset}</pos>
            <texture>
              <diffuse>model://area_xo/terrain/{os.path.basename(TEXTURE_PATH)}</diffuse>
              <normal>model://area_xo/terrain/{os.path.basename(NORMAL_MAP_PATH)}</normal>
              <size>{TERRAIN_SIZE_METERS}</size>
            </texture>
          </heightmap></geometry>
        </visual>
      </link>
    </model>"""


def polyline(points):
    return ''.join(f'<point>{east} {north}</point>' for east, north, *_ in points)


def building_geometry(outlines, height):
    return ''.join(
        f'<polyline>{polyline(outline)}<height>{height:.3f}</height></polyline>'
        for outline in outlines)


def buildings_model(buildings):
    elements = ''.join(f"""
        <visual name="building_{index}">
          <pose>0 0 {base_z:.3f} 0 0 0</pose>
          <geometry>{building_geometry(outlines, height)}</geometry>
          <material><diffuse>{BUILDING_COLOR}</diffuse><ambient>{BUILDING_COLOR}</ambient></material>
        </visual>
        <collision name="building_{index}">
          <pose>0 0 {base_z:.3f} 0 0 0</pose>
          <geometry>{building_geometry(outlines, height)}</geometry>
        </collision>""" for index, (outlines, base_z, height) in enumerate(buildings))
    return f"""
    <model name="buildings">
      <static>true</static>
      <link name="link">{elements}
      </link>
    </model>"""


def world_sdf(origin_height, heights, buildings):
    return f"""<?xml version="1.0" ?>
<sdf version="1.9">
  <world name="area_xo">
    <physics name="1ms" type="ignored">
      <max_step_size>0.001</max_step_size>
      <real_time_factor>1.0</real_time_factor>
      <dart>
        <collision_detector>bullet</collision_detector>
      </dart>
    </physics>
    <plugin filename="gz-sim-physics-system" name="gz::sim::systems::Physics"/>
    <plugin filename="gz-sim-user-commands-system" name="gz::sim::systems::UserCommands"/>
    <plugin filename="gz-sim-scene-broadcaster-system"
            name="gz::sim::systems::SceneBroadcaster"/>
    <plugin filename="gz-sim-sensors-system" name="gz::sim::systems::Sensors">
      <render_engine>ogre2</render_engine>
    </plugin>
    <plugin filename="gz-sim-navsat-system" name="gz::sim::systems::NavSat"/>
    <plugin filename="gz-sim-imu-system" name="gz::sim::systems::Imu"/>
    <plugin filename="gz-sim-contact-system" name="gz::sim::systems::Contact"/>

    <spherical_coordinates>
      <surface_model>EARTH_WGS84</surface_model>
      <world_frame_orientation>ENU</world_frame_orientation>
      <latitude_deg>{ORIGIN_LATITUDE_DEGREES}</latitude_deg>
      <longitude_deg>{ORIGIN_LONGITUDE_DEGREES}</longitude_deg>
      <elevation>{origin_height:.3f}</elevation>
      <heading_deg>0.0</heading_deg>
    </spherical_coordinates>

    <scene>
      <ambient>0.35 0.35 0.35 1</ambient>
      <background>0.7 0.8 0.9 1</background>
      <sky><clouds><speed>2</speed></clouds></sky>
      <grid>false</grid>
      <shadows>true</shadows>
    </scene>

    <light type="directional" name="sun">
      <cast_shadows>true</cast_shadows>
      <intensity>1.4</intensity>
      <pose>0 0 10 0 0 0</pose>
      <diffuse>0.85 0.85 0.85 1</diffuse>
      <specular>0.3 0.3 0.3 1</specular>
      <direction>-0.5 0.1 -0.9</direction>
    </light>
{terrain_model(origin_height, heights)}
{buildings_model(buildings)}
  </world>
</sdf>
"""


def spawn_pose(origin_height):
    [(east, north)] = transformed(
        WGS84_CRS, LOCAL_CRS, [(SPAWN_LONGITUDE_DEGREES, SPAWN_LATITUDE_DEGREES)],
        '-t_coord_epoch', str(COORDINATE_EPOCH_DECIMAL_YEAR))
    ground_height = height_at(HEIGHTMAP_PATH, east, north)
    return (round(east, 3), round(north, 3),
            round(ground_height - origin_height + SPAWN_CLEARANCE_METERS, 3), SPAWN_YAW_RADIANS)


def build():
    os.makedirs(TERRAIN_DIRECTORY, exist_ok=True)
    heightmap_path = heightmap(elevation(GROUND_COVERAGE, 'ground.tif'))
    surface_path = local_surface(elevation(SURFACE_COVERAGE, 'surface.tif'))
    texture(imagery())
    flat_normal_map()
    origin_height = height_at(heightmap_path, 0.0, 0.0)
    building_or_none = (
        building(feature, roof_height, origin_height)
        for feature, roof_height in building_statistics(
            heightmap_path, surface_path, local_footprints(footprints())))
    buildings = [candidate for candidate in building_or_none if candidate is not None]
    with open(WORLD_PATH, 'w') as world_file:
        world_file.write(world_sdf(origin_height, height_range(heightmap_path), buildings))
    return origin_height, len(buildings), spawn_pose(origin_height)


if __name__ == '__main__':
    origin_height, building_count, (spawn_east, spawn_north, spawn_height, spawn_yaw) = build()
    print(f'origin ellipsoidal height {origin_height:.3f} m')
    print(f'{building_count} buildings -> {WORLD_PATH}')
    print(f'spawn: x={spawn_east} y={spawn_north} z={spawn_height} yaw={spawn_yaw}')
